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


def test_one_query_failure_does_not_stop_others(client, monitor):
    from dataclasses import replace

    client.query.side_effect = [PermissionError(), ([{"latest_data_at": datetime.now(UTC)}], "id")]
    results = run_due(client, [monitor, replace(monitor, monitor_id=102)], [], 1)
    assert [r.status for r in results] == ["ERROR", "HEALTHY"]
