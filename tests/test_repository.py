from freshness_monitor.evaluator import Result
from freshness_monitor.repository import Repository


def test_persistence_parameterizes_and_is_idempotent(client, now):
    repo = Repository(client, "DATA_OBSERVABILITY")
    result = Result(101, now, None, None, "ERROR", 1, error_message="can't read")
    repo.save_result("run", result)
    first = client.query.call_args
    repo.save_result("run", result)
    assert client.query.call_args == first
    assert "can't read" not in first.args[0]
    assert "can't read" in first.args[1]
    assert "MERGE INTO" in first.args[0]
