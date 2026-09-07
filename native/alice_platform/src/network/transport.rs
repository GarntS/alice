//! Netlink connection/recovery seam. The legacy provider is replaced separately.
//!
//! Consumers must retain their last good snapshot on `Err`; an incomplete dump
//! is never published as an empty network. Dump callbacks must use `collect_dump`
//! rather than the clients' high-level streams (which hide multipart completion).

use std::{future::Future, io, time::Duration};

use futures_util::{Stream, StreamExt, stream::BoxStream};
use rtnetlink::{
    packet_core::{NLM_F_DUMP, NLM_F_DUMP_INTR, NLM_F_REQUEST, NetlinkMessage, NetlinkPayload},
    packet_route::{RouteNetlinkMessage, address::AddressMessage, link::LinkMessage},
    sys::AsyncSocket,
};
use tokio::{sync::mpsc, task::JoinHandle};

const RECEIVE_BUFFER_BYTES: i32 = 4 * 1024 * 1024;
const RETRY_DELAY: Duration = Duration::from_secs(1);
const REFRESH_INTERVAL: Duration = Duration::from_secs(1);
const DUMP_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CollectionError {
    Overrun,
    Interrupted,
    MissingCompletion,
    ConnectionLost,
    ConnectionPanicked,
    Timeout,
    Kernel(i32),
    Decode(String),
    Open(String),
}

/// SO_RCVBUF is best effort: Linux may cap the request at rmem_max. Never
/// use SO_RCVBUFFORCE, change sysctls, or require CAP_NET_ADMIN.
#[derive(Debug)]
pub struct ReceiveBuffer {
    pub requested_bytes: i32,
    /// Linux reports an effective value including doubled bookkeeping space.
    pub effective_bytes: Option<usize>,
    pub error: Option<String>,
}

fn enlarge_receive_buffer(
    set: impl FnOnce(i32) -> io::Result<()>,
    get: impl FnOnce() -> io::Result<usize>,
) -> ReceiveBuffer {
    let set_error = set(RECEIVE_BUFFER_BYTES).err();
    let effective = get();
    ReceiveBuffer {
        requested_bytes: RECEIVE_BUFFER_BYTES,
        error: set_error
            .or_else(|| {
                effective
                    .as_ref()
                    .err()
                    .map(|e| io::Error::new(e.kind(), e.to_string()))
            })
            .map(|e| e.to_string()),
        effective_bytes: effective.ok(),
    }
}

#[derive(Clone, Copy, Debug)]
enum Notification {
    Changed,
    Lost,
}

fn notification<T>(message: NetlinkMessage<T>) -> Option<Notification> {
    if message.header.flags & NLM_F_DUMP_INTR != 0 {
        return Some(Notification::Lost);
    }
    match message.payload {
        NetlinkPayload::Overrun(_) | NetlinkPayload::Error(_) => Some(Notification::Lost),
        NetlinkPayload::InnerMessage(_) => Some(Notification::Changed),
        _ => None,
    }
}

/// Owns the driver task so canceling/replacing a session closes the old socket.
/// Tokio contains an upstream request-associated Overrun panic in this task.
/// This requires Rust's default panic=unwind build, not panic=abort.
pub struct Session<H> {
    pub handle: H,
    pub receive_buffer: ReceiveBuffer,
    driver: JoinHandle<()>,
    notifications: BoxStream<'static, Notification>,
}

impl<H> Drop for Session<H> {
    fn drop(&mut self) {
        self.driver.abort();
    }
}

/// Subscribe before any dumps, with the larger buffer in place before binding.
pub fn open_route() -> io::Result<Session<rtnetlink::Handle>> {
    let (mut connection, handle, messages) = rtnetlink::new_connection()?;
    let socket = connection.socket_mut().socket_mut();
    let receive_buffer = enlarge_receive_buffer(
        |bytes| socket.set_rx_buf_sz(bytes),
        || socket.get_rx_buf_sz(),
    );
    let groups = [
        rtnetlink::MulticastGroup::Link,
        rtnetlink::MulticastGroup::Ipv4Ifaddr,
        rtnetlink::MulticastGroup::Ipv6Ifaddr,
    ]
    .into_iter()
    .fold(0, |mask, group| mask | (1 << (group as u32 - 1)));
    socket.bind(&rtnetlink::sys::SocketAddr::new(0, groups))?;
    connection.set_forward_done(true);
    Ok(Session {
        handle,
        receive_buffer,
        driver: tokio::spawn(connection),
        notifications: messages
            .filter_map(|(message, _)| async move { notification(message) })
            .boxed(),
    })
}

/// Opens only the unprivileged Generic Netlink transport. Callers may resolve
/// nl80211 and read GET_INTERFACE/GET_SCAN; no scan or WireGuard request is sent.
pub fn open_wifi() -> io::Result<Session<wl_nl80211::Nl80211Handle>> {
    let (mut connection, handle, messages) = wl_nl80211::new_connection()?;
    let socket = connection.socket_mut().socket_mut();
    let receive_buffer = enlarge_receive_buffer(
        |bytes| socket.set_rx_buf_sz(bytes),
        || socket.get_rx_buf_sz(),
    );
    connection.set_forward_done(true);
    Ok(Session {
        handle,
        receive_buffer,
        driver: tokio::spawn(connection),
        notifications: messages
            .filter_map(|(message, _)| async move { notification(message) })
            .boxed(),
    })
}

/// Raw observations are kept separate from UI classification. Both dumps must
/// finish successfully before the supervisor can publish this generation.
#[derive(Clone, Debug)]
pub struct RouteDump {
    pub links: Vec<LinkMessage>,
    pub addresses: Vec<AddressMessage>,
}

pub async fn dump_route(mut handle: rtnetlink::Handle) -> Result<RouteDump, CollectionError> {
    let mut links = Vec::new();
    let mut addresses = Vec::new();
    for payload in [
        RouteNetlinkMessage::GetLink(LinkMessage::default()),
        RouteNetlinkMessage::GetAddress(AddressMessage::default()),
    ] {
        let mut request = NetlinkMessage::from(payload);
        request.header.flags = NLM_F_REQUEST | NLM_F_DUMP;
        let responses = handle
            .request(request)
            .map_err(|error| CollectionError::Open(error.to_string()))?;
        for message in collect_dump(responses.map(Ok)).await? {
            match message {
                RouteNetlinkMessage::NewLink(link) => links.push(link),
                RouteNetlinkMessage::NewAddress(address) => addresses.push(address),
                _ => {
                    return Err(CollectionError::Decode(
                        "unexpected route dump response".into(),
                    ));
                }
            }
        }
    }
    Ok(RouteDump { links, addresses })
}

/// Read-only request construction, shared with the hermetic protocol tests.
fn wifi_request(
    interface: Option<u32>,
) -> NetlinkMessage<wl_nl80211::packet_generic::GenlMessage<wl_nl80211::Nl80211Message>> {
    use wl_nl80211::{Nl80211Attr, Nl80211Command, Nl80211Message, packet_generic::GenlMessage};
    let payload = Nl80211Message {
        cmd: if interface.is_some() {
            Nl80211Command::GetScan
        } else {
            Nl80211Command::GetInterface
        },
        attributes: interface.map(Nl80211Attr::IfIndex).into_iter().collect(),
    };
    let mut request = NetlinkMessage::from(GenlMessage::from_payload(payload));
    request.header.flags = NLM_F_REQUEST | NLM_F_DUMP;
    request
}

/// `None` enumerates Wi-Fi interfaces; `Some(ifindex)` reads that interface's
/// existing BSS cache. Family resolution is performed by the library. This does
/// not trigger a scan, even when the cache is empty or access is denied.
pub async fn dump_wifi(
    mut handle: wl_nl80211::Nl80211Handle,
    interface: Option<u32>,
) -> Result<Vec<wl_nl80211::Nl80211Message>, CollectionError> {
    let responses = handle
        .request(wifi_request(interface))
        .await
        .map_err(|error| CollectionError::Open(error.to_string()))?;
    let rows = collect_dump(
        responses
            .map(|message| message.map_err(|error| CollectionError::Decode(error.to_string()))),
    )
    .await?;
    Ok(rows.into_iter().map(|message| message.payload).collect())
}

/// Validate headers and the terminal status, retaining rows only after a
/// successful NLMSG_DONE. EOF, ACK, or a partial response is not completion.
pub async fn collect_dump<T>(
    stream: impl Stream<Item = Result<NetlinkMessage<T>, CollectionError>>,
) -> Result<Vec<T>, CollectionError> {
    futures_util::pin_mut!(stream);
    let mut rows = Vec::new();
    while let Some(message) = stream.next().await {
        let message = message?;
        if message.header.flags & NLM_F_DUMP_INTR != 0 {
            return Err(CollectionError::Interrupted);
        }
        match message.payload {
            NetlinkPayload::InnerMessage(row) => rows.push(row),
            NetlinkPayload::Done(done) if done.code == 0 => return Ok(rows),
            NetlinkPayload::Done(done) => return Err(CollectionError::Kernel(done.code)),
            NetlinkPayload::Error(error) => {
                if let Some(code) = error.code {
                    return Err(CollectionError::Kernel(code.get()));
                }
            }
            NetlinkPayload::Overrun(_) => return Err(CollectionError::Overrun),
            _ => {}
        }
    }
    Err(CollectionError::MissingCompletion)
}

impl<H: Clone> Session<H> {
    async fn run<T, F, Fut>(
        &mut self,
        dump: &mut F,
        snapshots: &mpsc::Sender<Result<T, CollectionError>>,
    ) -> Result<(), CollectionError>
    where
        F: FnMut(H) -> Fut,
        Fut: Future<Output = Result<T, CollectionError>>,
    {
        loop {
            // A new session always starts with fresh dumps. If events race with
            // collection, discard those rows and dump again before publishing.
            let mut dirty = false;
            let snapshot = {
                let collecting = dump(self.handle.clone());
                let deadline = tokio::time::sleep(DUMP_TIMEOUT);
                tokio::pin!(collecting, deadline);
                loop {
                    tokio::select! {
                        biased;
                        _ = snapshots.closed() => return Ok(()),
                        result = &mut self.driver => return Err(driver_error(result)),
                        _ = &mut deadline => return Err(CollectionError::Timeout),
                        event = self.notifications.next() => match event {
                            Some(Notification::Changed) => dirty = true,
                            Some(Notification::Lost) => return Err(CollectionError::Overrun),
                            None => return Err(CollectionError::ConnectionLost),
                        },
                        result = &mut collecting => break result?,
                    }
                }
            };
            if dirty {
                continue;
            }
            tokio::select! {
                biased;
                _ = snapshots.closed() => return Ok(()),
                result = &mut self.driver => return Err(driver_error(result)),
                event = self.notifications.next() => match event {
                    Some(Notification::Changed) => continue,
                    Some(Notification::Lost) => return Err(CollectionError::Overrun),
                    None => return Err(CollectionError::ConnectionLost),
                },
                result = snapshots.send(Ok(snapshot)) => if result.is_err() { return Ok(()); },
            }
            tokio::select! {
                biased;
                _ = snapshots.closed() => return Ok(()),
                result = &mut self.driver => return Err(driver_error(result)),
                event = self.notifications.next() => match event {
                    Some(Notification::Changed) => {},
                    Some(Notification::Lost) => return Err(CollectionError::Overrun),
                    None => return Err(CollectionError::ConnectionLost),
                },
                _ = tokio::time::sleep(REFRESH_INTERVAL) => {},
            }
        }
    }
}

fn driver_error(result: Result<(), tokio::task::JoinError>) -> CollectionError {
    if result.is_err_and(|error| error.is_panic()) {
        CollectionError::ConnectionPanicked
    } else {
        CollectionError::ConnectionLost
    }
}

/// Reopen and resubscribe after any failed generation. A bounded retry delay
/// avoids spinning when the kernel/backend is unavailable. Dropping the output
/// receiver stops the worker; canceling it also aborts the owned driver.
pub async fn supervise<H, T, Open, Dump, Fut>(
    mut open: Open,
    mut dump: Dump,
    snapshots: mpsc::Sender<Result<T, CollectionError>>,
) where
    H: Clone,
    Open: FnMut() -> io::Result<Session<H>>,
    Dump: FnMut(H) -> Fut,
    Fut: Future<Output = Result<T, CollectionError>>,
{
    loop {
        if snapshots.is_closed() {
            return;
        }
        let error = match open() {
            Ok(mut session) => match session.run(&mut dump, &snapshots).await {
                Ok(()) => return,
                Err(error) => error,
            },
            Err(error) => CollectionError::Open(error.to_string()),
        };
        if snapshots.send(Err(error)).await.is_err() {
            return;
        }
        tokio::select! {
            _ = snapshots.closed() => return,
            _ = tokio::time::sleep(RETRY_DELAY) => {},
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::stream;
    use rtnetlink::packet_core::{DoneMessage, ErrorMessage, NetlinkHeader};
    use std::num::NonZeroI32;

    fn packet(payload: NetlinkPayload<u8>) -> NetlinkMessage<u8> {
        NetlinkMessage::new(NetlinkHeader::default(), payload)
    }

    #[test]
    fn buffer_request_accepts_kernel_cap_and_permission_failure() {
        let capped = enlarge_receive_buffer(
            |size| {
                assert_eq!(size, 4 * 1024 * 1024);
                Ok(())
            },
            || Ok(425_984),
        );
        assert_eq!(capped.effective_bytes, Some(425_984));
        assert!(capped.error.is_none());
        let denied = enlarge_receive_buffer(
            |_| Err(io::Error::from(io::ErrorKind::PermissionDenied)),
            || Ok(212_992),
        );
        assert!(denied.error.is_some());
        assert_eq!(denied.effective_bytes, Some(212_992));
    }

    #[tokio::test]
    async fn dumps_require_successful_completion() {
        let row = packet(NetlinkPayload::InnerMessage(7));
        let done = packet(NetlinkPayload::Done(DoneMessage::default()));
        assert_eq!(
            collect_dump(stream::iter([Ok(row.clone()), Ok(done.clone())])).await,
            Ok(vec![7])
        );
        assert_eq!(collect_dump(stream::iter([Ok(done)])).await, Ok(vec![]));
        assert_eq!(
            collect_dump(stream::iter([Ok(row)])).await,
            Err(CollectionError::MissingCompletion)
        );
        assert_eq!(
            collect_dump(stream::iter([Ok(packet(NetlinkPayload::Error(
                ErrorMessage::default()
            )))]))
            .await,
            Err(CollectionError::MissingCompletion)
        );
    }

    #[tokio::test]
    async fn dumps_reject_interruption_overrun_and_kernel_errors() {
        let mut interrupted = packet(NetlinkPayload::Done(DoneMessage::default()));
        interrupted.header.flags = NLM_F_DUMP_INTR;
        let mut failed = DoneMessage::default();
        failed.code = -5;
        let mut denied = ErrorMessage::default();
        denied.code = NonZeroI32::new(-1);
        for (terminal, expected) in [
            (interrupted, CollectionError::Interrupted),
            (
                packet(NetlinkPayload::Overrun(vec![])),
                CollectionError::Overrun,
            ),
            (
                packet(NetlinkPayload::Done(failed)),
                CollectionError::Kernel(-5),
            ),
            (
                packet(NetlinkPayload::Error(denied)),
                CollectionError::Kernel(-1),
            ),
        ] {
            assert_eq!(
                collect_dump(stream::iter([
                    Ok(packet(NetlinkPayload::InnerMessage(7))),
                    Ok(terminal)
                ]))
                .await,
                Err(expected)
            );
        }
    }

    fn fake_session(
        id: usize,
        driver: impl Future<Output = ()> + Send + 'static,
        events: BoxStream<'static, Notification>,
    ) -> Session<usize> {
        Session {
            handle: id,
            receive_buffer: enlarge_receive_buffer(|_| Ok(()), || Ok(425_984)),
            driver: tokio::spawn(driver),
            notifications: events,
        }
    }

    #[tokio::test(start_paused = true)]
    async fn supervisor_reopens_and_redumps_after_panic_loss_or_overrun() {
        for failure in 0..3 {
            let (sender, mut receiver) = mpsc::channel(8);
            let mut generation = 0;
            let worker = tokio::spawn(supervise(
                move || {
                    generation += 1;
                    let current = generation;
                    Ok(fake_session(
                        current,
                        async move {
                            if current == 1 && failure == 0 {
                                panic!("simulated upstream overrun");
                            }
                            if current == 1 && failure == 1 {
                                return;
                            }
                            std::future::pending::<()>().await;
                        },
                        if current == 1 && failure == 2 {
                            stream::once(async { Notification::Lost })
                                .chain(stream::pending())
                                .boxed()
                        } else {
                            stream::pending().boxed()
                        },
                    ))
                },
                |generation| async move {
                    if generation == 1 {
                        std::future::pending::<()>().await;
                    }
                    Ok(generation)
                },
                sender,
            ));
            let expected = match failure {
                0 => CollectionError::ConnectionPanicked,
                1 => CollectionError::ConnectionLost,
                _ => CollectionError::Overrun,
            };
            assert_eq!(receiver.recv().await, Some(Err(expected)));
            assert_eq!(receiver.recv().await, Some(Ok(2)));
            drop(receiver);
            worker.await.unwrap();
        }
    }

    #[tokio::test(start_paused = true)]
    async fn timeout_reconnects_without_publishing_partial_state() {
        let (sender, mut receiver) = mpsc::channel(8);
        let mut generation = 0;
        let worker = tokio::spawn(supervise(
            move || {
                generation += 1;
                Ok(fake_session(
                    generation,
                    std::future::pending(),
                    stream::pending().boxed(),
                ))
            },
            |generation| async move {
                if generation == 1 {
                    std::future::pending::<()>().await;
                }
                Ok(generation)
            },
            sender,
        ));
        assert_eq!(receiver.recv().await, Some(Err(CollectionError::Timeout)));
        assert_eq!(receiver.recv().await, Some(Ok(2)));
        drop(receiver);
        worker.await.unwrap();
    }

    #[test]
    fn wifi_requests_only_read_interfaces_or_cached_bss() {
        use wl_nl80211::{Nl80211Attr, Nl80211Command};
        for (interface, command) in [
            (None, Nl80211Command::GetInterface),
            (Some(42), Nl80211Command::GetScan),
        ] {
            let request = wifi_request(interface);
            assert_eq!(request.header.flags, NLM_F_REQUEST | NLM_F_DUMP);
            let NetlinkPayload::InnerMessage(message) = request.payload else {
                panic!("missing request");
            };
            assert_eq!(message.payload.cmd, command);
            assert_eq!(
                message.payload.attributes,
                interface
                    .map(Nl80211Attr::IfIndex)
                    .into_iter()
                    .collect::<Vec<_>>()
            );
        }
    }

    #[tokio::test(start_paused = true)]
    async fn notifications_during_dump_force_reconciliation_then_periodic_refresh() {
        use std::sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        };
        let calls = Arc::new(AtomicUsize::new(0));
        let count = calls.clone();
        let (sender, mut receiver) = mpsc::channel(8);
        let worker = tokio::spawn(supervise(
            || {
                Ok(fake_session(
                    1,
                    std::future::pending(),
                    stream::once(async { Notification::Changed })
                        .chain(stream::pending())
                        .boxed(),
                ))
            },
            move |_| {
                let call = count.fetch_add(1, Ordering::SeqCst) + 1;
                async move { Ok(call) }
            },
            sender,
        ));
        // First dump races a notification and must never be published.
        assert_eq!(receiver.recv().await, Some(Ok(2)));
        assert_eq!(receiver.recv().await, Some(Ok(3)));
        assert_eq!(calls.load(Ordering::SeqCst), 3);
        drop(receiver);
        worker.await.unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn interrupted_dump_and_open_failure_retry_with_delay() {
        let (sender, mut receiver) = mpsc::channel(8);
        let mut generation = 0;
        let started = tokio::time::Instant::now();
        let worker = tokio::spawn(supervise(
            move || {
                generation += 1;
                if generation == 1 {
                    return Err(io::Error::other("unavailable"));
                }
                Ok(fake_session(
                    generation,
                    std::future::pending(),
                    stream::pending().boxed(),
                ))
            },
            |generation| async move {
                if generation == 2 {
                    Err(CollectionError::Interrupted)
                } else {
                    Ok(generation)
                }
            },
            sender,
        ));
        assert_eq!(
            receiver.recv().await,
            Some(Err(CollectionError::Open("unavailable".into())))
        );
        assert_eq!(
            receiver.recv().await,
            Some(Err(CollectionError::Interrupted))
        );
        assert_eq!(receiver.recv().await, Some(Ok(3)));
        assert!(started.elapsed() >= RETRY_DELAY * 2);
        drop(receiver);
        worker.await.unwrap();
    }

    #[tokio::test]
    async fn dropping_session_aborts_driver() {
        let session = fake_session(1, std::future::pending(), stream::pending().boxed());
        let driver = session.driver.abort_handle();
        drop(session);
        tokio::task::yield_now().await;
        assert!(driver.is_finished());
    }
}
