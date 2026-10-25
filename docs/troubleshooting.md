# Troubleshooting

| Symptom | Checks and action |
|---|---|
| ERROR for one monitor | Inspect sanitized audit ERROR_MESSAGE and SNOWFLAKE_QUERY_ID using authorized Snowflake query history. Verify SELECT/USAGE, uppercase metadata for unquoted objects, datetime column type, and statement timeout. Other monitors continue. |
| STALE with no lag | Empty table or all-null timestamp column; verify ingestion and correct column. |
| Future timestamp ERROR | Fix source time zone/clock. NTZ values must be UTC; do not raise thresholds to hide clock problems. |
| No new audit rows | Validate environment, key rotation, metadata validity, duplicate IDs, warehouse grants, gMSA permissions and task execution. Inspect RUNNING/ERROR runs. |
| Metadata validation fails | Check warning < critical, positive interval, supported cadence, only MAX_TIMESTAMP strategy, no expected-arrival payload, valid time zone, and unique IDs. |
| Task launch fails | Run Get-ScheduledTaskInfo; confirm gMSA availability/batch-logon rights, current release pointer, Scripts executable, and protected config ACLs. Exit 2 means command/setup failure; 1 means monitor errors. |
| Old metrics look healthy | Use the supplied recency-aware dashboards and recording rules. Verify Prometheus loaded rule_files. Do not replace original checked timestamps during manual exports. |
| Textfile collector error | Check enabled textfile collector, directory argument, .prom format, exporter read ACLs, and writable same-directory temporary files for the evaluator. |
| Dashboard empty | Verify datasource UID freshness-prometheus, Windows exporter job targets, enabled real monitors, and Prometheus recording rules. Disabled sample alone yields no active monitors. |
| Deployment fails | Candidate directory remains for diagnosis; active pointer reverts if switched. Never overwrite a failed release path: use a new version. Check wheelhouse Python/architecture compatibility and host secrets. |
| Service fails to start | Inspect WinSW logs, XML paths, LocalService ACLs, port conflicts, runtime prerequisites and vendor config errors. Reinstall matching verified dependencies on a replacement host. |
| Backup copy fails | Check disk space, ACLs, service stop status and robocopy codes (8+ indicates failure). Do not accept incomplete backups. |
| Notification missing | Confirm alert is firing, Grafana routing/contact point test or external Alertmanager config, outbound mail/webhook policy, and secrets. |

Never paste private keys, populated environment files, or unrestricted connector logs into tickets. Use query IDs with authorized query-history access. A networking/authentication outage produces sanitized errors; test Snowflake and required certificate endpoints under the service identity. Do not disable TLS verification.
