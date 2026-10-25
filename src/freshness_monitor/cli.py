"""Command-line entry point. Dry runs never write audit or metrics."""

import argparse
import logging
from dataclasses import asdict
from datetime import UTC, datetime
from uuid import uuid4

from . import __version__
from .config import Settings
from .logging_config import configure_logging
from .metrics_writer import atomic_write, render
from .repository import Repository
from .scheduler import exclusive_lock, run_due
from .snowflake_client import SnowflakeClient


def parser():
    root = argparse.ArgumentParser(prog="freshness-monitor")
    commands = root.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check")
    selection = check.add_mutually_exclusive_group(required=True)
    selection.add_argument("--all", action="store_true")
    selection.add_argument("--monitor-id", type=int)
    check.add_argument("--dry-run", action="store_true")
    check.add_argument("--force", action="store_true", help="Ignore per-monitor check interval")
    for name in ("validate-config", "test-connection", "export-metrics", "version"):
        commands.add_parser(name)
    return root


def export(repository, monitors, settings):
    rows = repository.current()
    success_rows, _ = repository.client.query(
        f"SELECT MAX(COMPLETED_AT) AS LAST_SUCCESS FROM {repository.db}.AUDIT.MONITOR_RUNS "
        "WHERE STATUS IN ('SUCCESS','PARTIAL')"
    )
    stamp = success_rows[0]["last_success"]
    atomic_write(
        settings.metrics_file, render(monitors, rows, stamp.timestamp() if stamp else None)
    )


def execute(args, settings, client):
    repository = Repository(client, settings.database)
    if args.command == "test-connection":
        client.query("SELECT CURRENT_VERSION() AS VERSION")
        return 0
    monitors = repository.monitors()
    if args.command == "validate-config":
        print(f"Validated {len(monitors)} monitors")
        return 0
    with exclusive_lock(str(settings.metrics_file) + ".lock"):
        if args.command == "export-metrics":
            export(repository, monitors, settings)
            return 0
        selected = [m for m in monitors if args.all or m.monitor_id == args.monitor_id]
        if not selected and args.monitor_id is not None:
            raise ValueError("Monitor ID was not found")
        started, run_id = datetime.now(UTC), str(uuid4())
        if not args.dry_run:
            repository.save_run(run_id, started, None, "RUNNING", 0, 0)
        try:
            results = run_due(client, selected, repository.current(), settings.workers, args.force)
            failed = sum(r.status == "ERROR" for r in results)
            for result in results:
                logging.info("monitor=%s status=%s", result.monitor_id, result.status)
                if args.dry_run:
                    print(asdict(result))
                else:
                    repository.save_result(run_id, result)
            if not args.dry_run:
                repository.save_run(
                    run_id,
                    started,
                    datetime.now(UTC),
                    "PARTIAL" if failed else "SUCCESS",
                    len(results),
                    failed,
                )
                export(repository, monitors, settings)
            return 1 if failed else 0
        except Exception as exc:
            if not args.dry_run:
                repository.save_run(
                    run_id, started, datetime.now(UTC), "ERROR", 0, 0, type(exc).__name__
                )
            raise


def main(argv=None):
    args = parser().parse_args(argv)
    if args.command == "version":
        print(__version__)
        return 0
    configure_logging()
    try:
        settings = Settings.from_env()
        return execute(args, settings, SnowflakeClient(settings))
    except Exception as exc:
        logging.error("command_failed type=%s", type(exc).__name__)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
