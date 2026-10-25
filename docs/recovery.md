# Disaster recovery

Initial planning targets are RPO 24 hours for Windows monitoring state and RTO four hours for a replacement host. These are **estimates, not tested results**. Snowflake config/audit durability and recovery depend on the account's retention/Time Travel policy and remain independent of the Windows disk. Prometheus can be rebuilt without losing Snowflake audit history, but its local time-series history is lost without a valid backup.

## Backup strategy

Run the offline backup script nightly during a maintenance window. It disables the task, refuses an active evaluation, stops Grafana/Prometheus for consistent SQLite/TSDB copies, and restarts previously running services in finally. Expect temporary monitoring gaps. Copy configuration (excluding designated secrets), data, immutable releases, WinSW metadata, task XML, and service-account/start metadata. A SHA256 manifest detects accidental corruption; it is not an authenticity signature. Secure the manifest with the backup and authenticate your off-host storage.

```powershell
.\scripts\recovery\backup.ps1 -Destination D:\BackupStaging\freshness-20261024
```

Destination must be new. Replicate the whole directory to encrypted, access-controlled off-host storage; a same-disk backup does not survive disk/server loss. Preserve approved vendor installers/checksums and the pipeline release zip separately. The backup omits `config/secrets` and `.p8/.pem/.key` files; recover credentials through your secret-management system. The Grafana database can contain contact point secrets, so encrypt the complete backup. The offline method avoids requiring Prometheus's administrative snapshot API. Do not copy a live TSDB or SQLite file outside this procedure.

Back up Snowflake configuration separately through approved account-native exports/clones or Time Travel retention; host backup does not export metadata tables. Keep change-controlled MERGE statements for monitor administration. Test accidental deletion recovery inside the account's actual retention window.

## Recovery order

1. Provision a patched replacement Windows Server, preferably the same directory root and drive layout. Recover domain gMSA authorization and network policies; fence the old evaluator host so only one writer exists.
2. Install the approved, pinned Python/Prometheus/Grafana/exporter/WinSW dependencies using verified intake hashes. Stop newly installed Grafana/Prometheus before restoring. If setup created data, use a clean data destination rather than overwriting it.
3. Restore configuration and secrets through their approved secure processes. Restore script checks a manifest and refuses existing Grafana DB/Prometheus WAL. It intentionally leaves services/task disabled until reviewed.
4. Restore monitoring persistent data if required; alternatively start an empty TSDB and accept the historical metrics loss explicitly.
5. Deploy the last working artifact and recreate its virtual environment; do not rely on moving a backed-up venv to a different path. Restored pointers/service paths contain absolute locations, so review them if the root changes. Use a new release version when redeploying after restore.
6. Reconfigure services and register the gMSA task to restore ACLs and bindings. Review generated Grafana INI before exposing internal access. Restore custom configuration from the backup as needed.
7. Test Snowflake connectivity and metadata validation under the service identity.
8. Force an audited evaluation and verify atomic metrics output.
9. Wait for Prometheus scraping and verify current evaluator timestamps and targets.
10. Validate dashboards, alert rules, contact points, and actual notification delivery; then enable the schedule and record recovery timings.

```powershell
Stop-Service FreshnessPrometheus,FreshnessGrafana
.\scripts\recovery\restore.ps1 -Backup D:\BackupStaging\freshness-20261024
# Deliver secrets, reinstall matching dependencies if missing, and recreate the release venv.
.\scripts\install\configure-services.ps1 -WinSWSha256 $approvedWinSWHash
.\scripts\run\register-scheduled-task.ps1 -ServiceAccount 'CONTOSO\FreshnessSvc$'
Disable-ScheduledTask DataFreshnessMonitor
.\scripts\deploy\deploy.ps1 -Artifact C:\SecureIntake\last-working.zip -Version recovery-20261024
.\scripts\recovery\verify-recovery.ps1
Enable-ScheduledTask DataFreshnessMonitor
Start-ScheduledTask DataFreshnessMonitor
```

`restore.ps1` validates every manifest-listed file before copying, checks manifest paths cannot escape the backup root, and does not mirror-delete destination data. Use trusted backups only. Keep installation/config files under administrator control. Dependency installers configure paths; the restore procedure requires checking that the restored service version paths exist on the replacement host. Recovery verification checks current metrics and ingestion, not only HTTP status.

## Failure scenarios

| Failure | Recovery |
|---|---|
| Server or disk loss | Fence old host, provision replacement, restore off-host backup and secrets, redeploy/re-register, verify. |
| TSDB corruption | Stop Prometheus, preserve corrupt data for investigation, restore consistent offline TSDB to a clean destination, restart and verify. Accept metrics loss explicitly if rebuilding empty. |
| Grafana config/database loss | Stop Grafana, restore config and SQLite from one consistent backup, restore credentials and test dashboard/contact-point access. |
| Evaluator failure | Validate config, permissions, key and package; redeploy last working release and run a forced check. |
| Failed software upgrade | Application rollback uses previous.txt. Service/config upgrade recovery restores matching binaries/config from approved intake/backup; pointer rollback alone does not revert services. |
| Expired/revoked credentials | Rotate/restore key through secret provider, verify grants, test connection under gMSA, perform audited evaluation. |
| Snowflake connectivity loss | Restore network/warehouse/account availability; retain prior audit history and allow missing-evaluation alerts. Do not refresh metric observation timestamps to hide outage. |
| Accidental config deletion | Use reviewed MERGEs or Snowflake Time Travel within configured retention; validate unique IDs before restarting. |

## Drill checklist

- [ ] Record incident start, backup age, versions, root path, and expected loss.
- [ ] Fence old host and confirm single active evaluator.
- [ ] Verify off-host backup manifest and credential recovery access.
- [ ] Rebuild host/services with no source production write privilege.
- [ ] Restore Grafana/TSDB and recreate the application environment.
- [ ] Run scheduled task under gMSA after a reboot; verify overlap prevention.
- [ ] Verify Snowflake durable history plus new audit rows and timestamps.
- [ ] Verify textfile, exporter, Prometheus targets, recording/alert rules, both dashboards.
- [ ] Simulate stale/null/query-error/missing metrics and test notification delivery.
- [ ] Record measured RPO/RTO, deviations and remediation; remove the replacement only after evidence is archived.
