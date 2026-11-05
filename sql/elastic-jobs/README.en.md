# Recurring stress every two hours with Elastic Jobs

[Español](README.md) | [SQL lab](../README.en.md)

**Preparation only: no Azure resources or load have been activated.** All four job
schedules are created **disabled**. Execution does not depend on VS Code, your
computer, or an open SQL client.

## Targets and execution

| Server | Database |
|---|---|
| `datasaturday01.database.windows.net` | `datasaturdaydb01` |
| `datasaturday02.database.windows.net` | `datasaturdaydb02` |

The coordinator asynchronously starts three independent jobs against **both** databases:

| Job | Call per database |
|---|---|
| `DemoStress-Deadlocks-A` | `EXEC SalesLT.GenerateDeadlocksUltra @Loops = 1000;` |
| `DemoStress-Deadlocks-B` | `EXEC SalesLT.GenerateDeadlocksUltra @Loops = 1000;` |
| `DemoStress-CpuIo` | `EXEC SalesLT.TableLockAndCpuIoStress @Loops = 100000;` |

This provides six load connections, three per database. A and B enable inter-session
deadlocks within each database; databases cannot block one another. Starts are not
exactly simultaneous, and late/failed connections can prevent deadlocks. Table-load
uses a separate table and does not by itself guarantee inter-session lock waits.

Only `DemoStress-Coordinator` gets a recurring schedule: **every two hours UTC**,
with no end date. A session application lock serializes coordinators. If **any worker
on either target remains active**, the entire cycle is omitted: no backlog, no
run-immediately-after-completion behavior, and no cancellation at two hours.
An intentional omission is recorded as **`Failed`, error 51001**, not the native
Elastic Jobs `Skipped` state. Steps have no automatic retries.

Coordinator success only confirms dispatch. Inspect worker and per-target results.
If dispatch fails midway, already-started workers continue and prevent a new cycle
while active. Workers have a **24-hour (86400-second) safety timeout** per target.
Inspect remaining sessions and rollback after failures/timeouts before resuming.
The guard cannot detect manual load or orphan sessions outside agent execution.
Do not manually start or schedule workers.

A continuously available schedule does **not** mean constant load between cycles.
Neither CPU saturation, physical I/O nor deadlocks are guaranteed: caching, five
Ultra rows, available capacity and `TOP 1000` affect the results.

## Identity and connection for each script

`REPLACE_JOB_AGENT_IDENTITY` is the **UAMI name**, not its resource ID,
client ID or principal/object ID. Use `MANAGED_IDENTITY_NAME` from
[`infra/.env`](../../infra/.env), or the Bicep output `jobIdentityName`. For example:

```sql
DECLARE @Identity SYSNAME = N'id-datasaturday-jobs';
```

Use the same name in both installation scripts. It is used in
`CREATE USER [id-datasaturday-jobs] FROM EXTERNAL PROVIDER`.

| Script | Connection server and database | Runs |
|---|---|---|
| [Grant_TargetPermissions.sql](Grant_TargetPermissions.sql) | `datasaturday01.database.windows.net` → `datasaturdaydb01` | Once in this database |
| [Grant_TargetPermissions.sql](Grant_TargetPermissions.sql) | `datasaturday02.database.windows.net` → `datasaturdaydb02` | Once in this database |
| [Configure_StressJobs.sql](Configure_StressJobs.sql) | Control server → `datasaturdayjobs` (or your job database name) | Once, only in the database associated with the agent |
| [Monitor_StressJobs.sql](Monitor_StressJobs.sql) | The same control server and job database | Whenever you need to inspect status |

**Do not run these scripts in `master`.** Grant permissions in both load databases;
run configuration and monitoring in the job database, not the load databases.
Check your connection before proceeding:

```sql
SELECT CONVERT(NVARCHAR(256), SERVERPROPERTY('ServerName')) AS ServerName,
       DB_NAME() AS DatabaseName;
```

Use an authorized Microsoft Entra administrator for installation. Monitoring only
requires read access to job views, for example through the `jobs_reader` role in
the job database.

## Setup without enabling load

New infrastructure can be prepared using the [Bicep template and parameter file](../../infra/README.md)
(deployment instructions in Spanish). No deployment is performed automatically.
That template now uses public access with firewall rules, without private endpoints;
verify network access on all three servers before installing jobs.

1. Provision a **dedicated job database**, separate from both load databases, preferably
   on a separate control server. Microsoft recommends S1 or above as a starting point.
   Create an **Elastic Job Agent** using that database and attach a **user-assigned
   managed identity (UAMI)**. System-assigned identity is not supported here.
   Both the agent and its database incur costs. These scripts do not provision them.
2. Configure Microsoft Entra and agent connectivity to **both load databases and the
   job database itself**, which is also a target. Approve agent-managed private
   endpoints on each applicable server if used; do not broadly open firewalls.
   Allow sufficient concurrent capacity for six workers plus the coordinator.
3. Install missing [tables](../CreateTable/Create_All_DemoTables.sql) and update
   [procedures](../StoredProcedure/Create_All_StoredProcedures.sql) on **both** targets.
   Creating tables destroys their data; never do this during a run. Updated Ultra
   bounds its payload to 200 characters, supports `READPAST` with
   `READ_COMMITTED_SNAPSHOT`, and only handles error 1205 internally. Unexpected
   errors from Ultra and CPU/I/O are rethrown to the agent.
4. Configure watcher/SRE separately and capture a baseline. This setup creates no
   alerts, incidents or SRE integrations.
5. As an authorized Microsoft Entra administrator, replace
   `REPLACE_JOB_AGENT_IDENTITY` in
   [Grant_TargetPermissions.sql](Grant_TargetPermissions.sql) and run it separately
   on each target. It grants execution and preflight table reads, not `db_owner`
   or direct write permissions.
6. Replace `REPLACE_JOB_SERVER`, `REPLACE_JOB_DATABASE` and
   `REPLACE_JOB_AGENT_IDENTITY` in [Configure_StressJobs.sql](Configure_StressJobs.sql).
   Run it **in that job database** with permission to administer jobs, create the
   user and grant permissions. It creates two target groups and four disabled jobs,
   without custom procedures or direct agent metadata modifications.
7. In that same job database, run [Monitor_StressJobs.sql](Monitor_StressJobs.sql).
   It is **read-only**: it does not start load or change schedules. Verify four jobs with
   **`enabled = 0`** and review the groups in the portal: two load targets and one
   control target.

Use a dedicated identity/agent: permission to start jobs in the control database
is not restricted to these three worker names. Configuration rejects existing demo
definitions rather than overwriting them. Review failures before retrying; never
delete definitions while jobs are active.

## Later validation and activation

**The following commands can start load; they are not installation steps.**
First temporarily lower worker loop counts with `jobs.sp_update_jobstep` or the
portal (for example 20 deadlock iterations and 10 CPU/I/O iterations). From the
**job database**, manually start one cycle, even though schedules are disabled:

```sql
EXEC jobs.sp_start_job @job_name = N'DemoStress-Coordinator';
```

Start the coordinator again while workers are active: expect 51001 and **no new
workers**. Verify six per-target executions and their sessions, actual 1205 events,
CPU, Data IO, Log IO, waits and errors, correlated with watcher/SRE.
Restore the requested aggressive counts, let the test finish, then enable **only
the coordinator** with a future UTC anchor:

```sql
DECLARE @FirstRunUtc DATETIME2 = DATEADD(MINUTE, 10, SYSUTCDATETIME());
EXEC jobs.sp_update_job
    @job_name = N'DemoStress-Coordinator',
    @enabled = 1,
    @schedule_start_time = @FirstRunUtc,
    @schedule_interval_type = N'Hours',
    @schedule_interval_count = 2;
```

This example starts ten minutes later and repeats every two hours. All three
workers remain disabled for scheduling; the coordinator starts them explicitly.

## Monitoring and stopping

[Monitor_StressJobs.sql](Monitor_StressJobs.sql) runs **in the control server's job
database** (`datasaturdayjobs` if you kept the example name), not in `master` or
the load databases. It is read-only and reads schedules and the latest 100
history rows, including UTC times, targets, lifecycle, execution IDs and messages.
Inspect workers too: the coordinator does not wait for them.

```sql
-- Prevent future cycles; this does NOT cancel active executions.
EXEC jobs.sp_update_job @job_name = N'DemoStress-Coordinator', @enabled = 0;

SELECT job_name, job_execution_id, lifecycle
FROM jobs.job_executions
WHERE job_name LIKE N'DemoStress-%' AND is_active = 1 AND step_id IS NULL;

-- Replace with an actual execution ID; repeat for each execution to cancel.
-- EXEC jobs.sp_stop_job @job_execution_id = 'EXECUTION-ID';
```

If active, stop the coordinator first (portal or `jobs.sp_stop_job`) and wait until
it is inactive **before** cancelling workers, avoiding new dispatches during shutdown.
Repeat inspection until no executions are active. Verify sessions, transactions
and rollback are finished on **both targets** before resetting tables. Delete
unneeded dedicated Azure resources after the demo to stop their costs; disabling
schedules does not remove the agent or its database.

## Offline checks without load

From the repository root:

```bash
python3 -m unittest discover -s sql/elastic-jobs -p 'test_*.py'
```

These are static contract checks for targets, disabled scheduling, commands, guards
and procedure consistency. They **do not compile or execute T-SQL**. Live permission,
concurrency and overlap validation remains pending in Azure and must use low loop
counts before enabling the recurring schedule.

## References

- [Elastic Jobs overview: identity, costs and job database as target](https://learn.microsoft.com/azure/azure-sql/database/elastic-jobs-overview)
- [Manage jobs using T-SQL](https://learn.microsoft.com/azure/azure-sql/database/elastic-jobs-tsql-create-manage)
- [sp_add_job scheduling](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-job-elastic-jobs-transact-sql)
