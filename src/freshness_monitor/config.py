"""Validated process and metadata configuration; secrets never enter reprs."""

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    account: str
    user: str
    role: str
    warehouse: str
    private_key_file: str
    database: str = "DATA_OBSERVABILITY"
    metrics_file: Path = Path(r"C:\DataObservability\data\textfile\freshness.prom")
    query_timeout: int = 60
    workers: int = 4
    retries: int = 2
    private_key_passphrase: str | None = field(default=None, repr=False)

    @classmethod
    def from_env(cls):
        def value(name, default=None):
            return os.environ.get("FRESHNESS_" + name, default)

        required = ["ACCOUNT", "USER", "ROLE", "WAREHOUSE", "PRIVATE_KEY_FILE"]
        if any(not value(k) for k in required):
            raise ValueError("Required FRESHNESS_* connection settings are missing")
        result = cls(
            **{k.lower(): value(k) for k in required},
            database=value("DATABASE", "DATA_OBSERVABILITY"),
            metrics_file=Path(value("METRICS_FILE", str(cls.metrics_file))),
            query_timeout=int(value("QUERY_TIMEOUT", "60")),
            workers=int(value("WORKERS", "4")),
            retries=int(value("RETRIES", "2")),
            private_key_passphrase=value("PRIVATE_KEY_PASSPHRASE"),
        )
        if not 1 <= result.workers <= 32 or not 1 <= result.query_timeout <= 600:
            raise ValueError("Workers must be 1..32 and query timeout 1..600 seconds")
        if not 0 <= result.retries <= 5:
            raise ValueError("Retries must be 0..5")
        return result


@dataclass(frozen=True)
class Monitor:
    monitor_id: int
    database_name: str
    schema_name: str
    table_name: str
    timestamp_column: str
    warning_threshold_minutes: float
    critical_threshold_minutes: float
    check_interval_minutes: int = 15
    enabled: bool = True
    owner_team: str = "unknown"
    cadence_type: str = "CUSTOM"
    strategy: str = "MAX_TIMESTAMP"
    time_zone: str = "UTC"
    expected_arrival: str | None = None

    def __post_init__(self):
        import math
        from zoneinfo import ZoneInfo

        if self.monitor_id < 1 or not all(
            (self.database_name, self.schema_name, self.table_name, self.timestamp_column)
        ):
            raise ValueError("Monitor ID and identifiers must be populated")
        warning, critical = self.warning_threshold_minutes, self.critical_threshold_minutes
        if not (math.isfinite(warning) and math.isfinite(critical) and 0 <= warning < critical):
            raise ValueError("Thresholds must be finite and 0 <= warning < critical")
        if self.check_interval_minutes < 1:
            raise ValueError("Check interval must be positive")
        if self.cadence_type not in {"HOURLY", "DAILY", "WEEKLY", "MONTHLY", "CUSTOM"}:
            raise ValueError("Unsupported cadence")
        if self.strategy != "MAX_TIMESTAMP" or self.expected_arrival is not None:
            raise ValueError("Only MAX_TIMESTAMP threshold evaluation is implemented")
        ZoneInfo(self.time_zone)
