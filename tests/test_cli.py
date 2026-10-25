import pytest

from freshness_monitor.cli import execute, main, parser


def test_version(capsys):
    assert main(["version"]) == 0
    assert "0.1.0" in capsys.readouterr().out


def test_selection_required():
    with pytest.raises(SystemExit):
        parser().parse_args(["check"])


def test_dry_run_no_writes(client, settings, now):
    client.query.side_effect = [([], None), ([], None)]
    args = parser().parse_args(["check", "--all", "--dry-run"])
    assert execute(args, settings, client) == 0
    assert not settings.metrics_file.exists()
    assert all("MERGE" not in call.args[0] for call in client.query.call_args_list)
