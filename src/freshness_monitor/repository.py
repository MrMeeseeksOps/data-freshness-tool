"""Metadata reads and idempotent audit MERGEs (one scheduled writer per account)."""

from dataclasses import fields
from uuid import NAMESPACE_URL, uuid5

from .config import Monitor
from .snowflake_client import identifier


class Repository:
    def __init__(self, client, database):
        self.client = client
        self.db = identifier(database)

    def monitors(self):
        columns = ",".join(f.name.upper() for f in fields(Monitor))
        rows, _ = self.client.query(f"SELECT {columns} FROM {self.db}.CONFIG.FRESHNESS_MONITORS")
        seen = set()
        monitors = []
        for row in rows:
            monitor = Monitor(**row)
            if monitor.monitor_id in seen:
                raise ValueError("Duplicate MONITOR_ID in metadata")
            seen.add(monitor.monitor_id)
            monitors.append(monitor)
        return monitors

    def merge(self, table, keys, values):
        columns = list(values)
        source = ",".join(f"%s AS {identifier(c)}" for c in columns)
        match = " AND ".join(f"t.{identifier(k)}=s.{identifier(k)}" for k in keys)
        updates = ",".join(f"t.{identifier(c)}=s.{identifier(c)}" for c in columns if c not in keys)
        names = ",".join(identifier(c) for c in columns)
        refs = ",".join(f"s.{identifier(c)}" for c in columns)
        self.client.query(
            f"MERGE INTO {self.db}.AUDIT.{table} t USING (SELECT {source}) s ON {match} "
            f"WHEN MATCHED THEN UPDATE SET {updates} "
            f"WHEN NOT MATCHED THEN INSERT ({names}) VALUES ({refs})",
            tuple(values.values()),
        )

    def save_result(self, run_id, result):
        from dataclasses import asdict

        values = {k.upper(): v for k, v in asdict(result).items()}
        values.update(
            RUN_ID=run_id, RESULT_ID=str(uuid5(NAMESPACE_URL, f"{run_id}:{result.monitor_id}"))
        )
        self.merge("FRESHNESS_RESULTS", ["RUN_ID", "MONITOR_ID"], values)

    def save_run(self, run_id, started, completed, status, evaluated, failed, error=None):
        self.merge(
            "MONITOR_RUNS",
            ["RUN_ID"],
            dict(
                RUN_ID=run_id,
                STARTED_AT=started,
                COMPLETED_AT=completed,
                STATUS=status,
                MONITORS_EVALUATED=evaluated,
                MONITORS_FAILED=failed,
                ERROR_MESSAGE=error,
            ),
        )

    def current(self):
        rows, _ = self.client.query(f"SELECT * FROM {self.db}.REPORTING.V_CURRENT_FRESHNESS")
        return rows
