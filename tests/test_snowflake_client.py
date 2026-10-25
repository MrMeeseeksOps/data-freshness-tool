from unittest.mock import MagicMock, Mock

import pytest

from freshness_monitor.snowflake_client import SnowflakeClient


class TransientError(Exception):
    sqlstate = "08006"


def test_transient_retry(settings):
    connection = MagicMock()
    cursor = connection.__enter__.return_value.cursor.return_value.__enter__.return_value
    cursor.description = [("X",)]
    cursor.fetchall.return_value = [(1,)]
    cursor.sfqid = "query"
    connect = Mock(side_effect=[TransientError(), connection])
    sleep = Mock()
    client = SnowflakeClient(settings, connect, sleep)
    assert client.query("SELECT 1") == ([{"x": 1}], "query")
    sleep.assert_called_once_with(1)
    assert connect.call_args.kwargs["session_parameters"]["STATEMENT_TIMEOUT_IN_SECONDS"] == 60


def test_permission_no_retry(settings):
    connect = Mock(side_effect=PermissionError("redacted"))
    with pytest.raises(PermissionError):
        SnowflakeClient(settings, connect).query("SELECT 1")
    assert connect.call_count == 1


def test_retry_exhaustion(settings):
    connect, sleep = Mock(side_effect=TransientError()), Mock()
    with pytest.raises(TransientError):
        SnowflakeClient(settings, connect, sleep).query("SELECT 1")
    assert connect.call_count == settings.retries + 1
    assert [c.args[0] for c in sleep.call_args_list] == [1, 2]


def test_ambiguous_login_not_retried(settings):
    error = TransientError()
    error.sqlstate = "08001"
    connect = Mock(side_effect=error)
    with pytest.raises(TransientError):
        SnowflakeClient(settings, connect).query("SELECT 1")
    assert connect.call_count == 1
