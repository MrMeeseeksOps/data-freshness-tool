from dataclasses import replace
from unittest.mock import patch

import pytest

from freshness_monitor.metrics_writer import atomic_write, render


def test_format(monitor, now):
    from prometheus_client.parser import text_string_to_metric_families

    payload = render(
        [replace(monitor, owner_team='a"b\\c\nx')],
        [
            {
                "monitor_id": 101,
                "status": "HEALTHY",
                "checked_at": now,
                "lag_seconds": 10,
                "query_duration_ms": 100,
            }
        ],
        now.timestamp(),
    )
    families = list(text_string_to_metric_families(payload))
    assert len(families) == 9
    assert "query_id" not in payload


def test_atomic_publish_and_failure(tmp_path):
    path = tmp_path / "x.prom"
    atomic_write(path, "old\n")
    with patch("os.replace", side_effect=OSError), pytest.raises(OSError):
        atomic_write(path, "new\n")
    assert path.read_text() == "old\n"
    assert list(tmp_path.iterdir()) == [path]
    atomic_write(path, "new\n")
    assert path.read_text() == "new\n"


def test_never_evaluated_sql_nulls(monitor):
    payload = render(
        [monitor],
        [{"monitor_id": 101, "status": "MISSING", "checked_at": None, "query_duration_ms": None}],
    )
    assert "data_freshness_evaluator_last_success_timestamp_seconds 0" in payload
    assert "data_freshness_lag_seconds{" not in payload
