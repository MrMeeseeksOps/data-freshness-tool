# Snowflake Data Freshness Monitoring

A metadata-driven monitor for detecting late production data without granting production write access. Python evaluates `MAX(timestamp_column)`, stores durable audit history in Snowflake, and publishes an atomic Prometheus textfile. windows_exporter serves the file, Prometheus stores metrics, and Grafana OSS presents freshness and host health. Windows Task Scheduler runs the evaluator every 15 minutes on one dedicated server. No containers or additional database server are required; Grafana uses its bundled SQLite database.

```text
Snowflake CONFIG -> Python evaluator -> Snowflake AUDIT -> REPORTING views
                         |
                  atomic freshness.prom
                         |
               windows_exporter :9182
                         |
                 Prometheus :9090 -> Grafana :3000
```

![Snowflake data freshness monitoring architecture](docs/architecture/data-freshness-architecture.png)

See the [architecture notes](docs/architecture/README.md) for implementation details and diagram corrections, including the Prometheus port and exported metric names.

## Repository

```text
.
├── README.md, pyproject.toml, .env.example, azure-pipelines.yml
├── src/freshness_monitor/
│   ├── cli.py, config.py, evaluator.py, snowflake_client.py
│   ├── repository.py, scheduler.py, metrics_writer.py, logging_config.py
│   └── __init__.py
├── sql/                         # six ordered provisioning scripts
├── config/
│   ├── prometheus/              # scrape configuration and alert/recording rules
│   ├── grafana/                 # two dashboards and datasource/dashboard/alert provisioning
│   └── windows-exporter/        # collector settings reference
├── scripts/
│   ├── common.ps1, validate-powershell.ps1
│   ├── install/                 # Python, Prometheus, Grafana, exporter, WinSW services
│   ├── run/                     # scheduled task and protected-environment launcher
│   ├── deploy/                  # candidate deployment, health verification, rollback
│   └── recovery/                # offline backup, restore, verification
├── docs/
│   ├── architecture/            # architecture diagram and implementation notes
│   └── *.md                    # deployment, security, operations, recovery, troubleshooting
└── tests/                       # mocked unit tests and opt-in nonproduction integration test
```

## Local development

Use Python 3.12 or newer. No Snowflake credentials are needed for unit tests. On macOS/Linux:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m ruff check src tests
python -m pytest -q
freshness-monitor version
```

On Windows:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
python -m pytest -q
.\scripts\validate-powershell.ps1
```

For packaging, run `python -m build`. CI builds a Windows Python 3.12 wheelhouse with the application and resolved binary dependencies so production deployment needs no package-index access. Dependency versions are bounded in `pyproject.toml`; the wheelhouse is the immutable dependency snapshot for each release. Rebuild artifacts after approved dependency updates.

## Snowflake setup and configuration

As an administrator, execute `sql/001` through `sql/006` in numeric order in a Snowflake worksheet or your approved SQL runner. Provision a small monitoring warehouse with auto-suspend, a noninteractive key-pair service user, and the explicit source grants described in [deployment](docs/deployment.md). Table DDL uses `IF NOT EXISTS`, reporting views use `CREATE OR REPLACE`, and the disabled sample uses `MERGE`; existing data is preserved. Future schema changes require reviewed migrations because `IF NOT EXISTS` does not alter existing tables.

Set process environment variables using `.env.example` as a reference. The Python CLI reads environment variables, not `.env` automatically. On the server the PowerShell launcher imports literal `FRESHNESS_NAME=value` lines from `config/secrets/monitor.env`; do not quote values or put commands in that file. Prefer an ACL-protected private key with a securely supplied passphrase. Never put secrets in pipeline arguments or source control.

Each enabled metadata row specifies exact Snowflake object names, a timestamp column, warning/critical lag thresholds, an owner, and a check interval. Identifiers are quoted individually, preserving case. Unquoted Snowflake objects usually require uppercase metadata. Duplicate monitor IDs fail metadata validation. Cadences HOURLY/DAILY/WEEKLY/MONTHLY/CUSTOM describe the monitor; thresholds determine classification. Business-day/time-zone/monthly deadline rules have reserved fields but are **not implemented**. Only `MAX_TIMESTAMP` is operational; other strategy names and populated expected-arrival rules are rejected. `Strategy` in the evaluator defines the extension contract.

All observations use UTC. `TIMESTAMP_NTZ` columns must contain UTC by contract; convert local source timestamps upstream. Null/empty tables are STALE with no lag sample. Timestamps more than five minutes into the future are ERROR; smaller clock skew is clamped to zero. Warning and critical thresholds are inclusive. Query/permission failures produce isolated ERROR results and sanitized exception types. Explicit connection-loss SQLSTATEs (08003/08006/08S01) and connection/timeout exceptions receive bounded exponential retries; ambiguous login failures and other failures fail immediately. Statement, login, and network timeouts are bounded separately.

```powershell
freshness-monitor check --all
freshness-monitor check --monitor-id 101 --force
freshness-monitor check --all --dry-run --force
freshness-monitor validate-config
freshness-monitor test-connection
freshness-monitor export-metrics
freshness-monitor version
```

A normal check evaluates only due enabled monitors. `--force` ignores check intervals. A dry run writes neither audit rows nor metrics. Exit codes: 0 success (including WARNING/STALE), 1 one or more monitor query errors, 2 command/configuration/persistence failure; argparse also uses 2 for invalid arguments. Sequential retries MERGE audit rows by run/monitor; standard Snowflake table keys do not enforce uniqueness. **Only one evaluator host may be active per metadata database.** Local file locking and Task Scheduler prevent host overlap; they are not a distributed lock.

## Metrics and dashboards

Status numbers are HEALTHY=0, WARNING=1, STALE=2, ERROR/MISSING=3. All seven required gauges are exported, with supplemental interval and critical-threshold gauges. Labels use monitor ID, database, schema, table, and owner; never query IDs, error text, or timestamps. Missing lag is omitted rather than reported as zero. Metrics use original checked-at timestamps, and exporting does not renew the evaluator heartbeat. Enabled gauges include disabled monitors with value zero.

The `data_freshness:healthy` recording rule requires a recent observation. Missing means the check interval plus a 15-minute scheduler grace has elapsed. Global heartbeat alerts after 30 minutes without a completed run; target absence/down and collector failures alert separately. Prometheus alert rules cover stale data, query errors, missing checks, stopped services, excessive lag, and compliance below 95%. Prometheus notifications require an external Alertmanager configured by the operator; rules still appear in Prometheus without one. Grafana additionally provisions an evaluator heartbeat alert. Configure Grafana contact points/routing and a test notification in the UI without committing credentials. Query failures are grouped together; the dashboard does not claim to distinguish network failure from permission failure.

Grafana starts at `http://127.0.0.1:3000`. Set a unique admin password while bound to loopback before allowing an internal interface. See [deployment](docs/deployment.md) for restricted access and service setup. The overview includes table counts, compliance, trends, owner groups, stale tables, last evaluator success, and missing observations. System health includes Windows CPU/memory/disk, target health, evaluation timing, and query failures.

## Installation, delivery, and recovery

Follow [deployment](docs/deployment.md) for Windows Server prerequisites, independently verified dependency hashes, gMSA permissions, installation, initial deployment, and Azure DevOps approvals. Use [operations](docs/operations.md) for routine checks and [troubleshooting](docs/troubleshooting.md) for failures. [Security](docs/security.md) covers credentials, grants, host ACLs, and network boundaries. [Recovery](docs/recovery.md) includes off-host backups, restore order, rollback, and a drill checklist.

The five pipeline stages are Validate, Test, Package, Deploy, Verify. Production deployment defaults off and requires a main-branch manual run with the deployment parameter enabled plus an Azure DevOps environment approval configured by an administrator. Deployment checks a new immutable release before updating `current.txt`; failed activation restores the prior pointer. SQL is packaged for review and is never automatically applied.

## Validation boundary

Local validation results are recorded in [docs/validation.md](docs/validation.md). Mocked tests do not prove Snowflake DDL/privileges or Windows installation correctness. Run a nonproduction installation and recovery drill before production. An optional read-only integration test runs when `FRESHNESS_INTEGRATION=nonproduction` and connection environment variables point to a dedicated test account.
