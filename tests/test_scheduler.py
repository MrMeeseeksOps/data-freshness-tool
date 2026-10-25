from datetime import UTC, datetime

import pytest

from freshness_monitor.scheduler import exclusive_lock, run_due


def test_lock(tmp_path):
    with exclusive_lock(tmp_path / "lock"):
        with pytest.raises(RuntimeError), exclusive_lock(tmp_path / "lock"):
            pass


def test_not_due(client, monitor):
    assert (
        run_due(client, [monitor], [{"monitor_id": 101, "checked_at": datetime.now(UTC)}], 2) == []
    )
