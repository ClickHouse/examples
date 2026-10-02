import asyncio
import threading
import unittest

from semantic_notes.service import DomainError
from semantic_notes.worker import EmbeddingWorker


class WorkerCancellation(unittest.IsolatedAsyncioTestCase):
    async def test_cancelled_request_keeps_capacity_until_thread_completion(self):
        gate = threading.Event()
        started = threading.Event()
        lock = threading.Lock()
        count = 0

        class BlockingEncoder:
            def embed(self, text):
                nonlocal count
                with lock:
                    count += 1
                    if count == 2:
                        started.set()
                if not gate.wait(5):
                    raise RuntimeError("test gate timed out")
                return text

        worker = EmbeddingWorker(BlockingEncoder())
        first = asyncio.create_task(worker.embed("one"))
        second = asyncio.create_task(worker.embed("two"))
        try:
            for _ in range(100):
                if started.is_set():
                    break
                await asyncio.sleep(0.01)
            self.assertTrue(started.is_set())
            first.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await first
            with self.assertRaises(DomainError) as busy:
                await worker.embed("three")
            self.assertEqual(busy.exception.status, 429)
            self.assertEqual(count, 2)
            gate.set()
            self.assertEqual(await second, "two")
            while worker.pending:
                await asyncio.sleep(0.01)
            self.assertEqual(await worker.embed("four"), "four")
        finally:
            gate.set()
            await asyncio.gather(first, second, return_exceptions=True)
