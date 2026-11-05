# Azure SQL watcher baseline analysis

**Skill name:** `azure-sql-watcher-baseline`

**Description:** Compare Azure SQL Database watcher telemetry in ADX with a
previous baseline and report evidence-backed anomalies without remediation.

## Purpose

Capture or validate a reference baseline and analyze a selected Azure SQL
Database watcher interval for deviations in:

- Prolonged blocking, lock waits, and timeouts.
- Confirmed deadlocks.
- CPU, data I/O, and log I/O.
- Session counts and wait types that help explain the other signals.

Use the connected Kusto/ADX tools only for read-only inspection and analysis.
Do not generate test load, execute SQL against a target database, terminate
sessions, or change Azure resources.

## Required inputs

Before querying, obtain:

1. The identity of the target logical server and database.
2. The baseline start and end timestamps in UTC.
3. The analysis start and end timestamps in UTC, unless the user only requests
   a baseline capture.
4. The lab scenario associated with the analysis interval, if known.

If any required input is missing, ask for it. Never silently choose intervals
or combine different SQL targets.

## Workflow

1. **Validate the source.** Confirm the active Kusto connector, cluster, and
   database. Discover the available tables and schemas using the connected
   read-only tools. Do not assume table or column names from another watcher
   deployment.
2. **Map the signals.** Identify the available timestamps, server/database
   dimensions, metric names and units, and event details. Check whether
   deadlock graphs/events are actually available. Record unavailable signals;
   do not replace them with unrelated metrics.
3. **Validate data quality.** Check that both UTC windows have sufficient
   samples, consistent units, and the same target identity. Report gaps,
   sampling frequency, and ingestion delay. If the windows or workloads are
   not comparable, mark those comparisons as `inconclusive`.
4. **Capture the baseline.** For continuous metrics, summarize the reference
   distribution with p50 and p95, using consistent aggregation and granularity.
   For discrete events, count confirmed events and affected sessions. State
   the interval and sample coverage.
5. **Analyze the selected interval.** Apply the same dimensions, units,
   aggregation, and granularity as the baseline. Highlight continuous values
   that exceed the reference p95 and report the relative difference when the
   calculation is meaningful. Compare confirmed event counts with the baseline.
6. **Correlate before concluding.** Use session identifiers and blocking
   relationships, wait types/durations, deadlock evidence, and nearby CPU or
   I/O changes when available. Distinguish an observed symptom from a cause
   supported by evidence.
7. **Report only supported conclusions.** Do not recommend or execute
   remediation unless the user requests it separately and the active safety
   policy permits it.

## Interpretation rules

- A lock timeout is not, by itself, a deadlock. Confirm deadlocks with available
  events/graphs or a correlated error 1205.
- Messages from a load generator do not prove that a deadlock occurred.
- Periodic sampling can miss brief events. State this limitation.
- A metric above the baseline p95 is a relative deviation, not necessarily
  a service-level violation or a root cause.
- Compare only the same server/database and periods with comparable workloads.
  If volume or configuration differs, state that explicitly.
- Do not infer a healthy state when telemetry is missing.
- Do not describe `sys.event_log` as a deadlock history source for Azure SQL
  Database.

## Required report

Return these sections:

1. **Outcome:** `anomaly observed`, `no deviation observed`, or `inconclusive`.
2. **Scope:** the target server/database and both UTC windows.
3. **Data quality:** source database, discovered tables/fields, coverage,
   units, ingestion gaps, and unavailable signals.
4. **Findings:** signal, baseline p50/p95 or event count, analysis value or
   count, relative difference when meaningful, affected sessions, evidence,
   and confidence (`high`, `medium`, or `low`).
5. **Correlation and limitations:** what the evidence supports, what it does
   not prove, and sampling or workload caveats.
6. **Next observation:** a non-destructive check the operator can perform.

Do not return an empty report that appears successful if the source, schema,
or required data cannot be read. Explain the blocker and mark the outcome as
`inconclusive`.

## Response language

Respond in Spanish. Preserve tool names, table names, metric names,
error codes, and KQL queries in their original form.
