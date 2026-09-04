//! Optional wlroots foreign-toplevel tracking and activation.
//!
//! All Wayland proxies stay private to the dedicated worker thread. Callers
//! communicate with the worker using normalized application identities.

use std::{
    io::{Read, Write},
    os::unix::net::UnixStream,
    sync::{Arc, OnceLock, mpsc},
};

use rustix::event::{PollFd, PollFlags, poll};
use wayland_client::{
    Connection, Dispatch, Proxy, QueueHandle,
    globals::{GlobalListContents, registry_queue_init},
    protocol::{wl_registry, wl_seat},
};
use wayland_protocols_wlr::foreign_toplevel::v1::client::{
    zwlr_foreign_toplevel_handle_v1, zwlr_foreign_toplevel_manager_v1,
};

const ACTIVATED_STATE: u32 = 2;

pub(crate) fn normalize_app_id(app_id: &str) -> Option<String> {
    crate::notifications::normalize_activation_identity(app_id)
}

#[derive(Debug)]
enum Command {
    Activate(String),
}

/// A cloneable command endpoint for the optional worker.
static ACTIVATION_SERVICE: OnceLock<ForeignToplevelActivationService> = OnceLock::new();

#[derive(Clone)]
pub(crate) struct ForeignToplevelActivationService {
    commands: mpsc::Sender<Command>,
    wake_writer: Arc<UnixStream>,
}

impl ForeignToplevelActivationService {
    pub(crate) fn start() -> Option<Self> {
        let (commands_tx, commands_rx) = mpsc::channel();
        let (wake_reader, wake_writer) = UnixStream::pair().ok()?;
        wake_reader.set_nonblocking(true).ok()?;
        wake_writer.set_nonblocking(true).ok()?;
        let wake_writer = Arc::new(wake_writer);
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);

        std::thread::Builder::new()
            .name("alice-foreign-toplevel".to_string())
            .spawn(move || match Worker::initialize(commands_rx, wake_reader) {
                Ok(mut worker) => {
                    let _ = ready_tx.send(Ok(()));
                    if let Err(error) = worker.run() {
                        eprintln!("alice: foreign-toplevel worker stopped: {error}");
                    }
                }
                Err(error) => {
                    let _ = ready_tx.send(Err(error));
                }
            })
            .ok()?;

        let readiness = ready_rx.recv().ok()?;
        initialization_succeeded(readiness).then_some(Self {
            commands: commands_tx,
            wake_writer,
        })
    }

    pub(crate) fn install_global(&self) {
        let _ = ACTIVATION_SERVICE.set(self.clone());
    }

    pub(crate) fn request_global_activation(identity: String) -> bool {
        ACTIVATION_SERVICE
            .get()
            .is_some_and(|service| service.request_activation(identity))
    }

    fn request_activation(&self, identity: String) -> bool {
        if self.commands.send(Command::Activate(identity)).is_err() {
            return false;
        }
        // A full wake socket still contains an unread wake byte, so the worker
        // will observe the queued command even if this write would block.
        let mut writer = &*self.wake_writer;
        match writer.write(&[1]) {
            Ok(_) => true,
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => true,
            Err(_) => false,
        }
    }
}

fn initialization_succeeded(result: Result<(), String>) -> bool {
    match result {
        Ok(()) => true,
        Err(error) => {
            eprintln!("alice: foreign-toplevel activation unavailable: {error}");
            false
        }
    }
}

struct Worker {
    event_queue: wayland_client::EventQueue<TrackerState>,
    state: TrackerState,
    commands: mpsc::Receiver<Command>,
    wake_reader: UnixStream,
}

impl Worker {
    fn initialize(
        commands: mpsc::Receiver<Command>,
        wake_reader: UnixStream,
    ) -> Result<Self, String> {
        let connection = Connection::connect_to_env().map_err(|error| error.to_string())?;
        let (globals, mut event_queue) =
            registry_queue_init::<TrackerState>(&connection).map_err(|error| error.to_string())?;
        let queue_handle = event_queue.handle();
        let manager = globals
            .bind::<zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1, _, _>(
                &queue_handle,
                1..=3,
                (),
            )
            .map_err(|error| format!("foreign-toplevel manager unavailable: {error}"))?;
        let seat = globals
            .bind::<wl_seat::WlSeat, _, _>(&queue_handle, 1..=9, ())
            .map_err(|error| format!("Wayland seat unavailable: {error}"))?;
        let mut state = TrackerState::new(manager, seat);
        event_queue
            .roundtrip(&mut state)
            .map_err(|error| error.to_string())?;

        Ok(Self {
            event_queue,
            state,
            commands,
            wake_reader,
        })
    }

    fn run(&mut self) -> Result<(), String> {
        while self.state.running {
            self.event_queue
                .dispatch_pending(&mut self.state)
                .map_err(|error| error.to_string())?;
            self.process_commands();
            self.event_queue
                .flush()
                .map_err(|error| error.to_string())?;

            let Some(read_guard) = self.event_queue.prepare_read() else {
                continue;
            };
            let (wayland_events, wake_events) = {
                let mut poll_fds = [
                    PollFd::new(&self.event_queue, PollFlags::IN),
                    PollFd::new(&self.wake_reader, PollFlags::IN),
                ];
                poll(&mut poll_fds, None).map_err(|error| error.to_string())?;
                (poll_fds[0].revents(), poll_fds[1].revents())
            };

            if wake_events.intersects(PollFlags::IN | PollFlags::HUP | PollFlags::ERR) {
                drop(read_guard);
                if !self.drain_wake_socket() {
                    self.state.running = false;
                    continue;
                }
                self.process_commands();
            } else if wayland_events.intersects(PollFlags::IN | PollFlags::HUP | PollFlags::ERR) {
                read_guard.read().map_err(|error| error.to_string())?;
            } else {
                drop(read_guard);
            }
        }
        Ok(())
    }

    fn drain_wake_socket(&mut self) -> bool {
        let mut buffer = [0_u8; 64];
        loop {
            match self.wake_reader.read(&mut buffer) {
                Ok(0) => return false,
                Ok(_) => {}
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => return true,
                Err(_) => return false,
            }
        }
    }

    fn process_commands(&mut self) {
        while let Ok(command) = self.commands.try_recv() {
            match command {
                Command::Activate(identity) => {
                    let _ = self.state.activate(&identity);
                }
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Candidate {
    key: u64,
    app_id: Option<String>,
    activated: bool,
    last_activation_sequence: Option<u64>,
}

fn update_activation_history(
    activated: &mut bool,
    last_activation_sequence: &mut Option<u64>,
    activation_sequence: &mut u64,
    new_activated: bool,
) {
    if new_activated && !*activated {
        *activation_sequence = activation_sequence.saturating_add(1);
        *last_activation_sequence = Some(*activation_sequence);
    }
    *activated = new_activated;
}

fn select_candidate(identity: &str, candidates: &[Candidate]) -> Option<u64> {
    let matches: Vec<&Candidate> = candidates
        .iter()
        .filter(|candidate| candidate.app_id.as_deref() == Some(identity))
        .collect();

    if matches.len() == 1 {
        return Some(matches[0].key);
    }

    let active: Vec<&Candidate> = matches
        .iter()
        .copied()
        .filter(|candidate| candidate.activated)
        .collect();
    if active.len() == 1 {
        return Some(active[0].key);
    }

    let most_recent = matches
        .iter()
        .filter_map(|candidate| candidate.last_activation_sequence)
        .max()?;
    let recent: Vec<&Candidate> = matches
        .iter()
        .copied()
        .filter(|candidate| candidate.last_activation_sequence == Some(most_recent))
        .collect();
    (recent.len() == 1).then_some(recent[0].key)
}

#[derive(Debug)]
struct TrackedToplevel {
    handle: zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
    app_id: Option<String>,
    title: String,
    activated: bool,
    creation_order: u64,
    last_activation_sequence: Option<u64>,
}

struct TrackerState {
    _manager: zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1,
    seat: wl_seat::WlSeat,
    toplevels: Vec<TrackedToplevel>,
    next_creation_order: u64,
    activation_sequence: u64,
    running: bool,
}

impl TrackerState {
    fn new(
        manager: zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1,
        seat: wl_seat::WlSeat,
    ) -> Self {
        Self {
            _manager: manager,
            seat,
            toplevels: Vec::new(),
            next_creation_order: 1,
            activation_sequence: 0,
            running: true,
        }
    }

    fn add_toplevel(
        &mut self,
        handle: zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
    ) {
        let creation_order = self.next_creation_order;
        self.next_creation_order = self.next_creation_order.saturating_add(1);
        self.toplevels.push(TrackedToplevel {
            handle,
            app_id: None,
            title: String::new(),
            activated: false,
            creation_order,
            last_activation_sequence: None,
        });
    }

    fn toplevel_mut(
        &mut self,
        handle: &zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
    ) -> Option<&mut TrackedToplevel> {
        let id = handle.id();
        self.toplevels
            .iter_mut()
            .find(|toplevel| toplevel.handle.id() == id)
    }

    fn update_activated(
        &mut self,
        handle: &zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
        activated: bool,
    ) {
        let id = handle.id();
        if let Some(index) = self
            .toplevels
            .iter()
            .position(|toplevel| toplevel.handle.id() == id)
        {
            let toplevel = &mut self.toplevels[index];
            update_activation_history(
                &mut toplevel.activated,
                &mut toplevel.last_activation_sequence,
                &mut self.activation_sequence,
                activated,
            );
        }
    }

    fn remove_toplevel(
        &mut self,
        handle: &zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
    ) {
        let id = handle.id();
        self.toplevels.retain(|toplevel| toplevel.handle.id() != id);
    }

    fn activation_target_key(&self, identity: &str) -> Option<u64> {
        let candidates: Vec<Candidate> = self
            .toplevels
            .iter()
            .map(|toplevel| Candidate {
                key: toplevel.creation_order,
                app_id: toplevel.app_id.clone(),
                activated: toplevel.activated,
                last_activation_sequence: toplevel.last_activation_sequence,
            })
            .collect();
        select_candidate(identity, &candidates)
    }

    fn activate(&self, identity: &str) -> bool {
        if !self.seat.is_alive() {
            return false;
        }
        let Some(key) = self.activation_target_key(identity) else {
            return false;
        };
        let Some(toplevel) = self
            .toplevels
            .iter()
            .find(|toplevel| toplevel.creation_order == key && toplevel.handle.is_alive())
        else {
            return false;
        };

        toplevel.handle.activate(&self.seat);
        true
    }
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for TrackerState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_registry::WlRegistry,
        _event: wl_registry::Event,
        _data: &GlobalListContents,
        _connection: &Connection,
        _queue_handle: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for TrackerState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_seat::WlSeat,
        _event: wl_seat::Event,
        _data: &(),
        _connection: &Connection,
        _queue_handle: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1, ()> for TrackerState {
    fn event(
        state: &mut Self,
        _proxy: &zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1,
        event: zwlr_foreign_toplevel_manager_v1::Event,
        _data: &(),
        _connection: &Connection,
        _queue_handle: &QueueHandle<Self>,
    ) {
        match event {
            zwlr_foreign_toplevel_manager_v1::Event::Toplevel { toplevel } => {
                state.add_toplevel(toplevel);
            }
            zwlr_foreign_toplevel_manager_v1::Event::Finished => state.running = false,
            _ => {}
        }
    }

    wayland_client::event_created_child!(
        TrackerState,
        zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1,
        [
            zwlr_foreign_toplevel_manager_v1::EVT_TOPLEVEL_OPCODE => (
                zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
                ()
            )
        ]
    );
}

impl Dispatch<zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1, ()> for TrackerState {
    fn event(
        state: &mut Self,
        proxy: &zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
        event: zwlr_foreign_toplevel_handle_v1::Event,
        _data: &(),
        _connection: &Connection,
        _queue_handle: &QueueHandle<Self>,
    ) {
        match event {
            zwlr_foreign_toplevel_handle_v1::Event::Title { title } => {
                if let Some(toplevel) = state.toplevel_mut(proxy) {
                    toplevel.title = title;
                }
            }
            zwlr_foreign_toplevel_handle_v1::Event::AppId { app_id } => {
                if let Some(toplevel) = state.toplevel_mut(proxy) {
                    toplevel.app_id = normalize_app_id(&app_id);
                }
            }
            zwlr_foreign_toplevel_handle_v1::Event::State { state: states } => {
                let activated = states.chunks_exact(4).any(|bytes| {
                    u32::from_ne_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) == ACTIVATED_STATE
                });
                state.update_activated(proxy, activated);
            }
            zwlr_foreign_toplevel_handle_v1::Event::Closed => {
                state.remove_toplevel(proxy);
                proxy.destroy();
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn candidate(
        key: u64,
        app_id: Option<&str>,
        activated: bool,
        last_activation_sequence: Option<u64>,
    ) -> Candidate {
        Candidate {
            key,
            app_id: app_id.map(str::to_string),
            activated,
            last_activation_sequence,
        }
    }

    #[test]
    fn app_ids_use_the_same_conservative_identity_normalization() {
        assert_eq!(
            normalize_app_id("  Org.Example.Chat.DESKTOP "),
            Some("org.example.chat".to_string())
        );
        assert_eq!(normalize_app_id(" .desktop "), None);
        assert_eq!(
            normalize_app_id("chat.desktop.desktop"),
            Some("chat.desktop".to_string())
        );
    }

    #[test]
    fn selection_requires_an_exact_normalized_identity_match() {
        let candidates = vec![
            candidate(1, Some("org.example.chat"), false, None),
            candidate(2, Some("org.example.chat-beta"), true, Some(2)),
            candidate(3, None, true, Some(3)),
        ];

        assert_eq!(select_candidate("org.example.chat", &candidates), Some(1));
        assert_eq!(select_candidate("org.example", &candidates), None);
    }

    #[test]
    fn selection_prefers_a_unique_active_match() {
        let candidates = vec![
            candidate(1, Some("chat"), false, Some(4)),
            candidate(2, Some("chat"), true, Some(2)),
        ];

        assert_eq!(select_candidate("chat", &candidates), Some(2));
    }

    #[test]
    fn selection_uses_unique_most_recent_activation_when_needed() {
        let candidates = vec![
            candidate(1, Some("chat"), false, Some(4)),
            candidate(2, Some("chat"), false, Some(7)),
            candidate(3, Some("chat"), false, Some(2)),
        ];

        assert_eq!(select_candidate("chat", &candidates), Some(2));
    }

    #[test]
    fn selection_rejects_absent_unmatched_and_ambiguous_candidates() {
        assert_eq!(select_candidate("chat", &[]), None);
        assert_eq!(
            select_candidate("chat", &[candidate(1, Some("mail"), true, Some(1))]),
            None
        );
        assert_eq!(
            select_candidate(
                "chat",
                &[
                    candidate(1, Some("chat"), false, None),
                    candidate(2, Some("chat"), false, None),
                ],
            ),
            None
        );
        assert_eq!(
            select_candidate(
                "chat",
                &[
                    candidate(1, Some("chat"), true, Some(5)),
                    candidate(2, Some("chat"), true, Some(5)),
                ],
            ),
            None
        );
    }

    #[test]
    fn activation_history_changes_only_on_inactive_to_active_transitions() {
        let mut activated = false;
        let mut last = None;
        let mut sequence = 0;

        update_activation_history(&mut activated, &mut last, &mut sequence, true);
        assert!(activated);
        assert_eq!(last, Some(1));
        assert_eq!(sequence, 1);

        update_activation_history(&mut activated, &mut last, &mut sequence, true);
        assert_eq!(last, Some(1));
        assert_eq!(sequence, 1);

        update_activation_history(&mut activated, &mut last, &mut sequence, false);
        update_activation_history(&mut activated, &mut last, &mut sequence, true);
        assert_eq!(last, Some(2));
        assert_eq!(sequence, 2);
    }

    #[test]
    fn removing_a_closed_candidate_removes_it_from_selection() {
        let mut candidates = vec![
            candidate(1, Some("chat"), true, Some(3)),
            candidate(2, Some("chat"), false, Some(2)),
        ];
        assert_eq!(select_candidate("chat", &candidates), Some(1));

        candidates.retain(|candidate| candidate.key != 1);
        assert_eq!(select_candidate("chat", &candidates), Some(2));

        candidates.clear();
        assert_eq!(select_candidate("chat", &candidates), None);
    }

    #[test]
    fn unsupported_initialization_is_optional() {
        assert!(!initialization_succeeded(Err(
            "manager unavailable".to_string()
        )));
        assert!(initialization_succeeded(Ok(())));
    }

    #[test]
    fn activation_request_queues_identity_and_wakes_worker() {
        let (commands_tx, commands_rx) = mpsc::channel();
        let (mut wake_reader, wake_writer) = UnixStream::pair().expect("socket pair");
        let service = ForeignToplevelActivationService {
            commands: commands_tx,
            wake_writer: Arc::new(wake_writer),
        };

        assert!(service.request_activation("org.example.chat".to_string()));
        assert!(matches!(
            commands_rx.recv().expect("activation command"),
            Command::Activate(identity) if identity == "org.example.chat"
        ));
        let mut byte = [0_u8; 1];
        wake_reader.read_exact(&mut byte).expect("wake byte");
        assert_eq!(byte, [1]);
    }
}
