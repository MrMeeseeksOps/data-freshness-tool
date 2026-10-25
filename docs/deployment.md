# Windows Server deployment

Use a dedicated, patched, domain-joined Windows Server 2022 or newer with 64-bit Python 3.12, PowerShell 5.1 or 7, .NET Framework 4.6.1+ for WinSW 2, trusted CA certificates, and synchronized time. Start sizing at 4 vCPU, 8 GB RAM, and 100 GB SSD; measure TSDB/cardinality and MAX-query costs before increasing monitors. This sizing is an estimate, not a load-test result. Reserve disk space for 30 days of Prometheus data plus local backup staging.

## Identities and network

Provision a dedicated domain gMSA, authorize the host to retrieve its managed password, install it with `Install-ADServiceAccount`, test with `Test-ADServiceAccount`, and grant Log on as a batch job through domain policy. Do not use a personal account or interactive password. WinSW services run as LocalService; the evaluator runs as the gMSA. Installers/agent need an administrator; the runtime does not. Limit Azure deployment agents to a dedicated secured pool; do not run untrusted PR code on that host.

Allow outbound Snowflake HTTPS 443 and the account's required certificate/revocation endpoints according to your Snowflake network policy. Installation/build hosts also need official vendor/package endpoints; production evaluator releases install offline. Prometheus and windows_exporter bind to 127.0.0.1 on 9090/9182. Initially bind Grafana to loopback on 3000, change its default admin password, and configure authentication. To expose it internally, use a specific private IP and a domain-profile firewall rule limited to approved subnets. Plain HTTP permits interception on the internal network: deploy an authenticated TLS reverse proxy, or configure Grafana TLS with managed certificates, before transmitting credentials across the network. No inbound public rules are created.

## Snowflake

Execute all six SQL scripts in order with provisioning/role administration privileges. Create a dedicated auto-suspending warehouse and service user; register its RSA public key and grant FRESHNESS_RUNTIME. Example object grants (replace the example names):

```sql
GRANT USAGE ON WAREHOUSE MONITORING_WH TO ROLE FRESHNESS_RUNTIME;
GRANT USAGE ON DATABASE EXAMPLE_PROD TO ROLE FRESHNESS_SOURCE_READ;
GRANT USAGE ON SCHEMA EXAMPLE_PROD.PUBLIC TO ROLE FRESHNESS_SOURCE_READ;
GRANT SELECT ON TABLE EXAMPLE_PROD.PUBLIC.ORDERS TO ROLE FRESHNESS_SOURCE_READ;
GRANT ROLE FRESHNESS_RUNTIME TO USER FRESHNESS_SERVICE;
```

No source write grants are needed. Configuration administration belongs to a separate operator role. Verify the view-owner role can read audit/config tables. Add real monitors through reviewed `MERGE`s with unique IDs; do not enable the sample until identifiers are replaced. Snowflake constraints are informational, so retain one evaluator host and one metadata-administration writer. Check duplicate IDs before enabling schedules.

## Dependency installation

Defaults pin Python 3.12.10, Prometheus 3.5.0, Grafana OSS 12.1.0, windows_exporter 0.31.3, and WinSW 2.12.0. These are reproducible baseline pins, not a claim that they are the latest secure versions. Review vendor advisories, approve newer pins, and validate in staging before production. Component installers expose a version parameter. `install-all.ps1` uses the baseline pins; invoke individual installers for an approved version change.

Obtain SHA256 values for the exact filenames from official release pages or vendor-published checksums/signatures. When no vendor checksum exists, verify the vendor artifact through your software intake/signature process and record its approved hash independently. Installation refuses missing or malformed hashes and mismatches. Python additionally requires a valid Python Software Foundation Authenticode signature. The WinSW wrapper is an explicit third-party dependency; review its release before approval. Do not invent hash values or copy an untrusted checksum beside a download.

Create a protected `C:\SecureIntake\checksums.json` with the approved SHA256 strings under keys `python`, `prometheus`, `grafana`, `windows_exporter`, `winsw`. Then from the repository or extracted artifact, in an elevated shell:

```powershell
.\scripts\install\install-all.ps1 -ChecksumsFile C:\SecureIntake\checksums.json
```

Install actions log to `C:\DataObservability\logs`. Verified archives are cached; persistent data is outside application directories. Current configs are preserved on repeated installs. Review/copy changed configuration files explicitly during upgrades; this is not automatic configuration migration. Back up first. `configure-services.ps1` recreates generated service XML and Grafana INI; retain site-specific changes as a reviewed configuration input before rerunning it.

Official references: [Python releases](https://www.python.org/downloads/windows/), [Prometheus downloads](https://prometheus.io/download/), [Grafana Windows installation](https://grafana.com/docs/grafana/latest/setup-grafana/installation/windows/), [windows_exporter MSI options](https://github.com/prometheus-community/windows_exporter), [WinSW v2](https://winsw.github.io/v2/).

## Secrets and initial application release

Create `C:\DataObservability\config\secrets` as administrator; populate `monitor.env` using `.env.example` and deliver the private key through your approved secret system. Do not populate these through a transcript or pipeline echo. Registering the task sets restrictive secret ACLs. For initial setup, secure the directory before placing secrets:

```powershell
$root = 'C:\DataObservability'
$account = 'CONTOSO\FreshnessSvc$'
New-Item -ItemType Directory "$root\config\secrets" -Force
icacls "$root\config\secrets" /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' "${account}:(OI)(CI)RX"
# Deliver monitor.env and the key now using the approved secret provider.
.\scripts\run\register-scheduled-task.ps1 -ServiceAccount $account
Disable-ScheduledTask DataFreshnessMonitor
```

Build/download the pipeline artifact. It contains the application wheel, a Windows Python 3.12 dependency wheelhouse, and scripts/config/docs/SQL. Check its SHA256 against the pipeline artifact record. Deploy:

```powershell
.\scripts\deploy\deploy.ps1 -Artifact C:\SecureIntake\0.1.0-123.zip -Version 0.1.0-123
Enable-ScheduledTask DataFreshnessMonitor
Start-ScheduledTask DataFreshnessMonitor
Get-ScheduledTaskInfo DataFreshnessMonitor
.\scripts\deploy\verify-deployment.ps1
```

The candidate is checked against live metadata with dry-run queries, then activates and performs an audited check. Verify checks services, endpoint readiness, current metrics, and Prometheus ingestion. If Grafana binds to a specific private IP, pass its URL to manual verification; pass `-GrafanaUrl` to `deploy.ps1` as well and set the same URL in the pipeline verification command before changing the bind address.

The task launcher imports protected config, selects the immutable release through `config/current.txt`, and logs evaluator events. Triggers run every 15 minutes and after startup; overlapping triggers are ignored. Manual checks also take a local advisory lock. Large monitor sets can exceed 15 minutes; tune warehouse, timeout, concurrency, and intervals to fit your run budget. Check for disabled/never-run monitors before go-live.

## Azure DevOps and upgrades

Configure hosted Windows builds and a self-hosted administrative Windows deployment agent in `DataObservabilityWindows`. Create the `data-observability-production` environment and mandatory approvers/checks in the Azure UI; YAML alone cannot enforce those approvals. Keep secrets on the protected host or inject through an approved secret provider; do not store real values in YAML. The default build validates and packages only. Enable `deployProduction` manually on main after approval.

Each release path is immutable. The deploy script disables the task, refuses an active evaluator, builds an offline virtual environment, validates the candidate, and switches the release pointer. It preserves the prior pointer and reverts it on failure. Verification failure in the final pipeline stage requires operator investigation; deploy activation has already performed its own verification. Config/service upgrades are explicit maintenance actions and are not part of application pointer rollback. Database-destructive changes are never applied by CI.

```powershell
.\scripts\recovery\backup.ps1
.\scripts\deploy\deploy.ps1 -Artifact C:\SecureIntake\0.1.0-124.zip -Version 0.1.0-124
# Revert application to the prior successfully active release:
.\scripts\deploy\rollback.ps1
Start-ScheduledTask DataFreshnessMonitor
```

Rollback checks the target before switching. It leaves data/config in place and does not reverse SQL migrations. Maintain backward-compatible schema changes and keep old releases until your retention policy expires. Test Windows installers, service recovery, task gMSA access, metric ingestion, both dashboards, and notification delivery in staging before go-live.
