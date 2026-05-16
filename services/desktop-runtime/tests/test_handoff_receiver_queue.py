from __future__ import annotations

import asyncio
import time
from unittest.mock import AsyncMock, MagicMock

import pytest

from desktop_runtime.adapters.types import HandoffPayload, TaskContext
from desktop_runtime.handoff_receiver import HandoffReceiver


def make_handoff(handoff_id: str, task_id: str) -> HandoffPayload:
    return HandoffPayload(
        handoff_id=handoff_id,
        task_id=task_id,
        source_run_id=f"run-{handoff_id}",
        target_runtime="desktop",
        permission_level="local_only",
        checkpoint_data=None,
        task_context=TaskContext(
            intent_summary="test task",
            permission_level="local_only",
            allowed_tools=[],
        ),
        initiated_by="user",
        initiated_at="2026-05-16T00:00:00+00:00",
        reason="test",
        run_id=f"run-{handoff_id}",
    )


def make_receiver() -> HandoffReceiver:
    worker = MagicMock()
    reporter = MagicMock()
    reporter.report = AsyncMock()
    client = MagicMock()
    return HandoffReceiver(worker=worker, reporter=reporter, client=client)


@pytest.mark.anyio
async def test_serial_execution() -> None:
    """Three concurrent receive() calls should execute serially via the semaphore.

    Each mocked execute_run sleeps 0.1 s, so serial execution must take >= 0.3 s.
    Concurrent execution would finish in ~0.1 s.
    """
    call_count = 0

    async def slow_execute(payload: HandoffPayload) -> None:
        nonlocal call_count
        call_count += 1
        await asyncio.sleep(0.1)

    receiver = make_receiver()
    receiver._worker.execute_run = slow_execute

    handoffs = [make_handoff(f"h{i}", f"task-{i}") for i in range(3)]

    start = time.monotonic()
    await asyncio.gather(*[receiver.receive(h) for h in handoffs])
    elapsed = time.monotonic() - start

    assert call_count == 3
    assert elapsed >= 0.3, (
        f"Expected serial execution (>= 0.3 s) but finished in {elapsed:.3f} s — "
        "handoffs may have run concurrently"
    )


@pytest.mark.anyio
async def test_semaphore_blocks_new_run() -> None:
    """A second receive() must not start execute_run while the first still holds the semaphore."""
    first_entered = asyncio.Event()
    first_may_exit = asyncio.Event()
    second_entered = asyncio.Event()

    async def gated_execute(payload: HandoffPayload) -> None:
        if payload.handoff_id == "h0":
            first_entered.set()
            await first_may_exit.wait()
        else:
            second_entered.set()

    receiver = make_receiver()
    receiver._worker.execute_run = gated_execute

    # Start h0 — it will hold the semaphore until we release it.
    task0 = asyncio.create_task(receiver.receive(make_handoff("h0", "task-0")))
    await first_entered.wait()

    # Start h1 while h0 holds the semaphore.
    task1 = asyncio.create_task(receiver.receive(make_handoff("h1", "task-1")))
    # Yield control so task1 can run as far as the semaphore acquire (but not past it).
    await asyncio.sleep(0)
    await asyncio.sleep(0)

    assert not second_entered.is_set(), (
        "h1 started execute_run while h0 still held the semaphore"
    )
    assert receiver._active_run_count == 1

    # Release h0 and let both tasks finish.
    first_may_exit.set()
    await task0
    await task1

    assert second_entered.is_set()
    assert receiver._active_run_count == 0
