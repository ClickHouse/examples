use crate::error::ApiError;
use actix_web::web;
use std::sync::Arc;
use tokio::sync::Semaphore;

#[derive(Clone)]
pub struct BlockingGate(Arc<Semaphore>);

impl BlockingGate {
    pub fn new(capacity: usize) -> Self {
        Self(Arc::new(Semaphore::new(capacity)))
    }

    pub async fn run<F, T>(&self, operation: F) -> Result<T, ApiError>
    where
        F: FnOnce() -> Result<T, ApiError> + Send + 'static,
        T: Send + 'static,
    {
        let permit = self
            .0
            .clone()
            .try_acquire_owned()
            .map_err(|_| ApiError::unavailable())?;
        web::block(move || {
            // The closure owns admission through checkout and SQL. Dropping the HTTP
            // future does not release capacity while its blocking work continues.
            let _permit = permit;
            operation()
        })
        .await
        .map_err(|_| ApiError::unavailable())?
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    #[actix_web::test]
    async fn cancelled_waiter_keeps_actual_work_admitted() {
        let gate = BlockingGate::new(1);
        let (started, ready) = tokio::sync::oneshot::channel();
        let (release, wait) = mpsc::channel();
        let running = gate.clone();
        let task = actix_web::rt::spawn(async move {
            running
                .run(move || {
                    started.send(()).unwrap();
                    wait.recv_timeout(std::time::Duration::from_secs(5))
                        .unwrap();
                    Ok(())
                })
                .await
        });
        ready.await.unwrap();
        task.abort();
        assert!(gate.run(|| Ok(())).await.is_err());
        release.send(()).unwrap();
        for _ in 0..100 {
            if gate.run(|| Ok(())).await.is_ok() {
                return;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        panic!("blocking closure did not release capacity after finishing");
    }
}
