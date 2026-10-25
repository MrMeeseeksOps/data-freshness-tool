"""Pure classification and isolated MAX_TIMESTAMP evaluation."""

import time
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from .snowflake_client import identifier


class Strategy(Protocol):
    def latest(self, client, monitor) -> tuple[datetime | None, str | None]: ...


class MaxTimestamp:
    def latest(self, client, monitor):
        table = ".".join(
            identifier(v) for v in (monitor.database_name, monitor.schema_name, monitor.table_name)
        )
        rows, query_id = client.query(
            f"SELECT MAX({identifier(monitor.timestamp_column)}) AS LATEST_DATA_AT FROM {table}"
        )
        return rows[0]["latest_data_at"], query_id


@dataclass(frozen=True)
class Result:
    monitor_id: int
    checked_at: datetime
    latest_data_at: datetime | None
    lag_seconds: float | None
    status: str
    query_duration_ms: float
    snowflake_query_id: str | None = None
    error_message: str | None = None


def utc(value):
    # Snowflake TIMESTAMP_NTZ is interpreted as UTC by explicit platform contract.
    if not isinstance(value, datetime):
        raise ValueError("Timestamp column must return a datetime")
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def classify(latest, now, warning_minutes, critical_minutes):
    if latest is None:
        return "STALE", None
    lag = (utc(now) - utc(latest)).total_seconds()
    if lag < -300:
        return "ERROR", lag
    lag = max(0, lag)
    if lag >= critical_minutes * 60:
        return "STALE", lag
    if lag >= warning_minutes * 60:
        return "WARNING", lag
    return "HEALTHY", lag


def evaluate(client, monitor, now=None, strategy=None):
    checked = utc(now or datetime.now(UTC))
    start = time.monotonic()
    try:
        latest, query_id = (strategy or MaxTimestamp()).latest(client, monitor)
        latest = utc(latest) if latest is not None else None
        status, lag = classify(
            latest, checked, monitor.warning_threshold_minutes, monitor.critical_threshold_minutes
        )
        return Result(
            monitor.monitor_id,
            checked,
            latest,
            lag,
            status,
            (time.monotonic() - start) * 1000,
            query_id,
            "Future timestamp exceeds five-minute tolerance" if status == "ERROR" else None,
        )
    except Exception as exc:
        # Raw connector errors can contain SQL, credentials, and customer data.
        return Result(
            monitor.monitor_id,
            checked,
            None,
            None,
            "ERROR",
            (time.monotonic() - start) * 1000,
            error_message=type(exc).__name__,
        )
