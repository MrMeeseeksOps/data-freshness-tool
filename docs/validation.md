# Validation record

Local validation on October 24, 2026 used macOS ARM64 and Python 3.14.3. This is development validation; the Windows release pipeline targets Python 3.12.

| Check | Result |
|---|---|
| Editable package installation with runtime/dev dependencies | Passed |
| Ruff lint | Passed |
| Pytest mocked/unit suite | 27 passed, 1 optional live integration test skipped |
| Prometheus text format and escaped labels | Parsed with prometheus-client in tests |
| Atomic replacement failure | Existing file preserved; temporary file cleaned |
| Source archive and wheel build | Passed |
| Installed CLI version | 0.1.0 |
| Python dependency consistency | pip check passed |
| PowerShell parsing | All scripts passed PowerShell 7.5.3 native parser |
| YAML/JSON syntax | All configuration files and pipeline YAML parsed |
| Prometheus scrape configuration and 11 rules | Passed Prometheus 3.5.0 promtool |
| Recency regression | promtool rule test proves an unchanged healthy file becomes missing/unhealthy |

Portable PowerShell and Prometheus validation tools were fetched from their official GitHub releases into a temporary directory and matched vendor release SHA256 checksums. They are not runtime project dependencies and are not committed.

The tests cover threshold boundaries, empty/null/future data, unsafe identifier quoting, query isolation, configuration bounds, metadata duplicates, bounded retries and login non-retry, audit MERGE parameterization/idempotency, CLI selection/dry-run behavior, due-time scheduling, local overlap locking, metrics parsing and atomic publishing. The optional integration test is read-only and requires an explicit nonproduction opt-in.

Not validated locally: real Snowflake DDL/view semantics and grants, Snowflake timeout/connector behavior against a real account, Windows MSI/EXE installs and vendor archive layouts, gMSA/group-policy behavior, Windows PowerShell 5.1 execution, native services/recovery, firewall enforcement, Grafana import/provisioning/notification delivery, Azure DevOps hosted builds/environment approvals, offline Windows wheelhouse deployment, and a complete backup/restore/reboot drill. YAML parsing checks syntax and does not replace Azure DevOps pipeline validation.

No architecture image was available; the required PNG path is documented without fabricating an asset. MAX_TIMESTAMP is the sole implemented strategy. Calendar/business-day/monthly expected-arrival evaluation and differentiated Snowflake connection-failure metrics require future implementation. Production rollout must follow docs/deployment.md and the recovery drill checklist, recording real measurements and failures before approval.

## Reproduce

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m ruff check src tests
python -m pytest -q
python -m build
freshness-monitor version
```

With PowerShell available, run `pwsh -NoProfile -File scripts/validate-powershell.ps1`. On Windows, `scripts/validate-prometheus.ps1` downloads and verifies the pinned validation tools; alternatively run `promtool check config config/prometheus/prometheus.yml` and `promtool test rules tests/prometheus-rules.yml` with a trusted installation.
