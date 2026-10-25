"""Prometheus textfile snapshots; retain original observation timestamps on export."""

import math
import os
import tempfile
from pathlib import Path

from .evaluator import utc

STATUS = {"HEALTHY": 0, "WARNING": 1, "STALE": 2, "ERROR": 3, "MISSING": 3}


def escape(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def render(monitors, rows, last_success=None):
    current = {row["monitor_id"]: row for row in rows}
    samples = {}

    def emit(name, labels, value):
        if value is not None and math.isfinite(float(value)):
            samples.setdefault(name, []).append(f"{name}{labels} {float(value):.9g}")

    for monitor in monitors:
        labels = (
            "{"
            + ",".join(
                f'{key}="{escape(value)}"'
                for key, value in (
                    ("monitor_id", monitor.monitor_id),
                    ("database", monitor.database_name),
                    ("schema", monitor.schema_name),
                    ("table", monitor.table_name),
                    ("owner_team", monitor.owner_team),
                )
            )
            + "}"
        )
        emit("data_freshness_monitor_enabled", labels, monitor.enabled)
        emit("data_freshness_check_interval_seconds", labels, monitor.check_interval_minutes * 60)
        emit(
            "data_freshness_critical_threshold_seconds",
            labels,
            monitor.critical_threshold_minutes * 60,
        )
        row = current.get(monitor.monitor_id, {})
        checked = row.get("checked_at")
        status = row.get("status", "MISSING")
        emit("data_freshness_status", labels, STATUS.get(status, 3))
        emit(
            "data_freshness_last_check_timestamp_seconds",
            labels,
            utc(checked).timestamp() if checked else 0,
        )
        emit("data_freshness_lag_seconds", labels, row.get("lag_seconds"))
        emit(
            "data_freshness_evaluation_duration_seconds",
            labels,
            (row.get("query_duration_ms") or 0) / 1000,
        )
        emit("data_freshness_evaluation_success", labels, status in {"HEALTHY", "WARNING", "STALE"})
    emit("data_freshness_evaluator_last_success_timestamp_seconds", "", last_success or 0)
    return (
        "\n".join(
            line
            for name, values in sorted(samples.items())
            for line in [
                f"# HELP {name} Freshness monitor {name.removeprefix('data_freshness_')}.",
                f"# TYPE {name} gauge",
                *values,
            ]
        )
        + "\n"
    )


def atomic_write(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=path.parent, suffix=".tmp", delete=False
        ) as handle:
            name = handle.name
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)
