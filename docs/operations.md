# Operations

Check `DataFreshnessMonitor` task history/result, `logs/evaluator.log`, exporter collector success, Prometheus targets, Grafana alert state, and Snowflake REPORTING.V_CURRENT_FRESHNESS daily. The latest view detects missing checks using each interval plus 15 minutes. Status values: 0 HEALTHY, 1 WARNING, 2 STALE, 3 ERROR/MISSING. Query success is independent of data freshness: a successful query can report STALE.

```powershell
Get-Service FreshnessPrometheus,FreshnessGrafana,windows_exporter
Get-ScheduledTaskInfo DataFreshnessMonitor
Start-ScheduledTask DataFreshnessMonitor
Get-Content C:\DataObservability\logs\evaluator.log -Tail 50
Invoke-RestMethod http://127.0.0.1:9090/api/v1/targets
```

Run CLI commands in the release environment with protected variables imported (see `scripts/common.ps1`). `validate-config` checks all metadata, including disabled rows; `test-connection` checks the service connection; `check --all --force --dry-run` evaluates without writes. `export-metrics` rebuilds from durable audit observations and does not refresh observation time or heartbeat. Metadata validation is fail-closed; a bad configuration row stops the run, and heartbeat alerts detect the stalled evaluator. Individual query failures remain isolated.

Change monitors with reviewed MERGE statements using stable IDs. Check thresholds, exact identifier case, owner, enabled flag, and timestamp UTC semantics. Disabled monitors remain in metadata/metrics with enabled=0 and are excluded from compliance. The SQL current view labels old results MISSING, and PromQL recency gating prevents old healthy values remaining healthy if the evaluator stops. Removing monitors removes their series on the next successful textfile update.

Set Grafana notification contact points and routing through the authenticated UI or protected provisioning. Test actual delivery. The example Grafana heartbeat alert and Prometheus alerts can duplicate notifications; choose routing deliberately. Prometheus needs an operator-managed Alertmanager for delivery. This repository does not install Alertmanager. Monitor this server externally as well: a stopped Prometheus cannot deliver its own alerts.

Prometheus retention defaults to 30 days; Snowflake history retention is your policy and independent of this host. Track disk capacity and warehouse credits. Rotate evaluator logs with a site-approved scheduled log rotation while the task is idle (the launcher appends); WinSW rotates service logs. Do not allow logs/backups to fill the metrics volume. Restrict and encrypt off-host backups. Perform a recovery drill after dependency/configuration changes and at least quarterly. Record actual recovery timings.
