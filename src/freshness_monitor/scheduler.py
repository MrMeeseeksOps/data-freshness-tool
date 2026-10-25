"""Bounded evaluation, persisted due times, and a local cross-process lock."""

from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path

from .evaluator import evaluate, utc


@contextmanager
def exclusive_lock(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        handle.seek(0)
        handle.write(b"0")
        handle.flush()
        handle.seek(0)
        try:
            if __import__("os").name == "nt":
                import msvcrt

                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise RuntimeError("Another evaluator is running") from exc
        try:
            yield
        finally:
            if __import__("os").name == "nt":
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle, fcntl.LOCK_UN)


def run_due(client, monitors, current, workers, force=False):
    now = datetime.now(UTC)
    last = {row["monitor_id"]: row.get("checked_at") for row in current}
    due = [
        m
        for m in monitors
        if m.enabled
        and (
            force
            or not last.get(m.monitor_id)
            or (now - utc(last[m.monitor_id])).total_seconds() >= m.check_interval_minutes * 60
        )
    ]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(lambda monitor: evaluate(client, monitor), due))
