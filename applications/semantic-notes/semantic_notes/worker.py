import asyncio

import anyio

from .service import DomainError


class EmbeddingWorker:
    def __init__(self, encoder):
        self.encoder = encoder
        self.slots = asyncio.BoundedSemaphore(2)
        self.pending = set()

    async def embed(self, text):
        if self.slots.locked():
            raise DomainError("The encoder is busy. Please try again shortly.", 429)
        await self.slots.acquire()
        try:
            task = asyncio.create_task(
                anyio.to_thread.run_sync(
                    self.encoder.embed, text, abandon_on_cancel=False
                )
            )
        except BaseException:
            self.slots.release()
            raise
        self.pending.add(task)

        def finished(done):
            self.pending.discard(done)
            self.slots.release()
            # Retrieve errors even if the requesting task was cancelled.
            if not done.cancelled():
                done.exception()

        task.add_done_callback(finished)
        # A directly cancelled HTTP task cannot cancel the inner worker or release
        # its permit. The completion callback owns capacity until CPU work ends.
        return await asyncio.shield(task)
