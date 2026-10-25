"""Short-lived, thread-confined connections with bounded transient retries."""

import time


def identifier(value: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ValueError("Invalid Snowflake identifier")
    return '"' + value.replace('"', '""') + '"'


class SnowflakeClient:
    def __init__(self, settings, connect=None, sleep=time.sleep):
        self.settings = settings
        self._connect = connect
        self.sleep = sleep

    def query(self, sql, params=(), *, retry=True):
        connect = self._connect
        if connect is None:
            from snowflake.connector import connect
        for attempt in range(self.settings.retries + 1):
            try:
                with connect(
                    account=self.settings.account,
                    user=self.settings.user,
                    role=self.settings.role,
                    warehouse=self.settings.warehouse,
                    private_key_file=self.settings.private_key_file,
                    private_key_file_pwd=self.settings.private_key_passphrase,
                    login_timeout=30,
                    network_timeout=self.settings.query_timeout + 15,
                    session_parameters={
                        "TIMEZONE": "UTC",
                        "STATEMENT_TIMEOUT_IN_SECONDS": self.settings.query_timeout,
                        "QUERY_TAG": "freshness-monitor",
                    },
                ) as connection:
                    with connection.cursor() as cursor:
                        cursor.execute(sql, params, timeout=self.settings.query_timeout)
                        rows = cursor.fetchall() if cursor.description else []
                        columns = [c[0].lower() for c in cursor.description or []]
                        return [dict(zip(columns, row)) for row in rows], cursor.sfqid
            except Exception as exc:
                # Retry only connection-class SQLSTATEs; never retry auth/SQL/permission errors.
                transient = str(getattr(exc, "sqlstate", "")).startswith("08")
                if not retry or not transient or attempt == self.settings.retries:
                    raise
                self.sleep(2**attempt)
