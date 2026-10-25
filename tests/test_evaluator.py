from datetime import timedelta

import pytest

from freshness_monitor.evaluator import classify, evaluate
from freshness_monitor.snowflake_client import identifier


@pytest.mark.parametrize(
    "minutes,status",
    [(0, "HEALTHY"), (60, "WARNING"), (120, "STALE"), (-6, "ERROR"), (-1, "HEALTHY")],
)
def test_classification(now, minutes, status):
    assert classify(now - timedelta(minutes=minutes), now, 60, 120)[0] == status


def test_empty(now):
    assert classify(None, now, 60, 120) == ("STALE", None)


def test_query_failure_isolated(client, monitor, now):
    client.query.side_effect = PermissionError("secret")
    result = evaluate(client, monitor, now)
    assert result.status == "ERROR"
    assert result.error_message == "PermissionError"


def test_max_query(client, monitor, now):
    client.query.return_value = ([{"latest_data_at": now.replace(tzinfo=None)}], "query123")
    assert evaluate(client, monitor, now).status == "HEALTHY"
    assert 'MAX("LOADED_AT")' in client.query.call_args.args[0]


def test_identifier_quoting():
    assert identifier('a"; DROP TABLE X;--') == '"a""; DROP TABLE X;--"'
    with pytest.raises(ValueError):
        identifier("x\0y")
