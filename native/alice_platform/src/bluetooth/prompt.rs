//! One-active-request broker shared by BlueZ agent callbacks and Flutter.

use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};
use tokio::sync::oneshot;

use crate::{
    bluetooth::service::BluetoothSnapshotCache,
    runtime::Trigger,
    state::{BluetoothPrompt, BluetoothPromptKind},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PromptResponse {
    PinCode(String),
    Passkey(u32),
    Accept,
    Deny,
    Cancel,
}

struct ActivePrompt {
    token: String,
    sender: oneshot::Sender<PromptResponse>,
}

#[derive(Clone)]
pub struct PromptBroker {
    cache: BluetoothSnapshotCache,
    trigger: tokio::sync::mpsc::Sender<Trigger>,
    next_token: Arc<AtomicU64>,
    active: Arc<Mutex<Option<ActivePrompt>>>,
}

impl PromptBroker {
    pub fn new(cache: BluetoothSnapshotCache, trigger: tokio::sync::mpsc::Sender<Trigger>) -> Self {
        Self {
            cache,
            trigger,
            next_token: Arc::new(AtomicU64::new(1)),
            active: Arc::new(Mutex::new(None)),
        }
    }

    /// Reject concurrent and unsolicited BlueZ requests rather than assigning a
    /// response to the wrong device.
    pub fn open(
        &self,
        address: String,
        device_label: String,
        kind: BluetoothPromptKind,
        passkey: Option<u32>,
        service: Option<String>,
    ) -> Result<oneshot::Receiver<PromptResponse>, ()> {
        let token = format!("bt-{}", self.next_token.fetch_add(1, Ordering::Relaxed));
        let (sender, receiver) = oneshot::channel();
        let mut active = self
            .active
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if active.is_some() {
            return Err(());
        }
        *active = Some(ActivePrompt {
            token: token.clone(),
            sender,
        });
        self.cache.update(|snapshot| {
            snapshot.prompt = Some(BluetoothPrompt {
                token,
                address,
                device_label,
                kind,
                passkey,
                service,
            })
        });
        let _ = self.trigger.try_send(Trigger::Event);
        Ok(receiver)
    }

    /// Token validation makes late responses and responses to superseded cards harmless.
    pub fn respond(&self, token: &str, response: PromptResponse) -> bool {
        let mut active_slot = self
            .active
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let Some(active) = active_slot.take() else {
            return false;
        };
        if active.token != token {
            *active_slot = Some(active);
            return false;
        }
        drop(active_slot);
        self.cache.update(|snapshot| snapshot.prompt = None);
        let _ = self.trigger.try_send(Trigger::Event);
        let _ = active.sender.send(response);
        true
    }

    pub fn cancel(&self) {
        if let Some(active) = self
            .active
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take()
        {
            self.cache.update(|snapshot| snapshot.prompt = None);
            let _ = self.trigger.try_send(Trigger::Event);
            let _ = active.sender.send(PromptResponse::Cancel);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::BluetoothPromptKind;

    fn broker() -> PromptBroker {
        let (trigger, _receiver) = tokio::sync::mpsc::channel(4);
        PromptBroker::new(BluetoothSnapshotCache::default(), trigger)
    }

    #[tokio::test]
    async fn routes_a_response_only_to_its_active_token() {
        let broker = broker();
        let response = broker
            .open(
                "AA:BB".into(),
                "Device".into(),
                BluetoothPromptKind::RequestPinCode,
                None,
                None,
            )
            .unwrap();
        let token = broker.cache.snapshot().prompt.unwrap().token;
        assert!(!broker.respond("stale", PromptResponse::PinCode("1234".into())));
        assert!(broker.respond(&token, PromptResponse::PinCode("1234".into())));
        assert_eq!(
            response.await.unwrap(),
            PromptResponse::PinCode("1234".into())
        );
        assert!(broker.cache.snapshot().prompt.is_none());
    }

    #[tokio::test]
    async fn cancellation_resolves_the_active_request() {
        let broker = broker();
        let response = broker
            .open(
                "AA:BB".into(),
                "Device".into(),
                BluetoothPromptKind::DisplayPasskey,
                Some(123456),
                None,
            )
            .unwrap();
        broker.cancel();
        assert_eq!(response.await.unwrap(), PromptResponse::Cancel);
        assert!(broker.cache.snapshot().prompt.is_none());
    }

    #[test]
    fn rejects_concurrent_prompts() {
        let broker = broker();
        let _first = broker
            .open(
                "AA:BB".into(),
                "Device".into(),
                BluetoothPromptKind::AuthorizeDevice,
                None,
                None,
            )
            .unwrap();
        assert!(
            broker
                .open(
                    "CC:DD".into(),
                    "Other".into(),
                    BluetoothPromptKind::AuthorizeDevice,
                    None,
                    None
                )
                .is_err()
        );
    }
}
