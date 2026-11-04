# SQL stress lab

[Español](README.md)

Use this lab to generate contention, long blocking, deadlocks, and CPU/I/O load in a test database and observe monitoring behavior, for example with Azure SQL Database watcher. These scripts do not deploy resources or configure monitoring. The `loadtesting` folder is outside this guide's scope.

> **Use an isolated lab environment only.** The scripts modify data, can consume resources, and may incur costs. Table creation scripts drop existing demo tables and their data. Never run them in production.

## Prerequisites

- A test database in Azure SQL Database or SQL Server supporting `CREATE OR ALTER PROCEDURE`.
- A client such as SQL Server Management Studio (SSMS) or the MSSQL extension for VS Code. The combined procedure script requires a client that interprets `GO`.
- Permissions to create tables and procedures in `SalesLT`, drop demo tables, and execute procedures. Diagnostic views require additional permissions depending on platform and version.
- Multiple independent connections to the **same database**. Running several statements in a single session is not sufficient.
- Monitoring configured beforehand, with access to metrics, sessions, waits, and deadlock capture if available.

## 1. Prepare the database

Confirm the target before running destructive scripts:

```sql
SELECT DB_NAME() AS DatabaseName, @@SPID AS SessionId;
```

The scripts use `SalesLT` but do not create it. If missing, create it using an authorized identity:

```sql
IF SCHEMA_ID(N'SalesLT') IS NULL
    EXEC(N'CREATE SCHEMA SalesLT AUTHORIZATION dbo;');
```

1. Run [Create_All_DemoTables.sql](CreateTable/Create_All_DemoTables.sql).
2. Run [Create_All_StoredProcedures.sql](StoredProcedure/Create_All_StoredProcedures.sql).
3. Check the initial data:

```sql
SELECT 'DeadlockStress' AS TableName, COUNT(*) AS RowCount FROM SalesLT.DeadlockStress
UNION ALL
SELECT 'DeadlockUltra', COUNT(*) FROM SalesLT.DeadlockUltra
UNION ALL
SELECT 'LongBlockTest', COUNT(*) FROM SalesLT.LongBlockTest
UNION ALL
SELECT 'TableLockStress', COUNT(*) FROM SalesLT.TableLockStress;
```

Expected counts are **4, 5, 3, and 5000**. You can also prepare individual scenarios; see the [table](CreateTable/README.en.md) and [procedure](StoredProcedure/README.en.md) guides.

## 2. Capture a baseline

Before generating load, record the time, CPU, data I/O, log I/O, sessions, and waits. Record the connection count and parameters for each test. Open another connection for diagnostics and keep monitoring visible.

## 3. Run the scenarios

Start with a few iterations and test each scenario separately. Run the examples without an outer transaction.

### Long blocking and timeout

In connection A:

```sql
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 30;
```

While A is still running, execute in connection B:

```sql
EXEC SalesLT.TryAccessBlockedRow @Id = 1;
```

A holds an exclusive lock until `COMMIT`. B attempts to update the same row and normally prints a timeout message after about five seconds. Once A finishes, repeat B to observe an unblocked update. Use a third connection to observe blocked sessions and `LCK_M_*` waits.

### Deadlocks

Run this call concurrently in two or more connections:

```sql
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 10;
```

To try the higher-contention variant, run in multiple connections:

```sql
EXEC SalesLT.GenerateDeadlocksUltra @Loops = 20;
```

The procedures update random pairs of rows; concurrency encourages lock cycles but **does not guarantee deadlocks on every run**. Aggressive waits five seconds per iteration; Ultra waits 300 ms and adds reads. Total duration also depends on blocking and available resources.

### Table locking and CPU/I/O load

```sql
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 10;
```

This updates all 5000 rows with `TABLOCKX` and performs additional calculations and reads. Increase iterations gradually if the load is insufficient. Multiple sessions using this table can produce contention.

Saturation and high physical I/O are not guaranteed: caching, execution plans, and database capacity matter. The procedure's cross join is limited by `TOP 1000`.

### Combined runner

[Run_All_StressProcedures.sql](exec/Run_All_StressProcedures.sql) runs all procedures **sequentially**, using 100, 500, and 1000 iterations for the respective load generators. It does not create concurrent connections. On its own, it does not demonstrate inter-session deadlocks or the timeout above, because it accesses the row after the blocking call finishes. See the [execution guide](exec/README.en.md).

## 4. Observe results

During tests, use another connection to the database:

```sql
SELECT session_id, status, blocking_session_id,
       wait_type, wait_time, wait_resource
FROM sys.dm_exec_requests
WHERE session_id <> @@SPID
ORDER BY blocking_session_id DESC, session_id;
```

- Correlate timestamps and session IDs with blocking, waits, CPU, data I/O, and log I/O.
- A lock timeout is not a deadlock. Confirm deadlocks using the events or deadlock graphs available on your platform.
- Allow for sampling and ingestion intervals: a short event may not appear in a periodic capture.
- `Deadlock detectado` messages are not sufficient evidence: both generators print this text for **any caught error**, not just error 1205. The table-load procedure does not report errors it catches.

[bloqueos.sql](exec/bloqueos.sql) contains notes, not an executable batch: it uses `#` headings that are invalid T-SQL comments, a placeholder user, and a `sys.event_log` query that should not be treated as a portable deadlock history. See the warnings in the [execution guide](exec/README.en.md).

## 5. Stop and reset

1. Let calls finish or cancel **every connection** generating load.
2. After cancellation or an error, check the state in that same connection:

   ```sql
   SELECT @@TRANCOUNT AS OpenTransactions, XACT_STATE() AS TransactionState;
   -- Only if a lab transaction remains open:
   IF @@TRANCOUNT > 0
       ROLLBACK;
   ```

   Cancellation does not guarantee immediate rollback. If the connection is lost, an administrator should check affected sessions; do not terminate unrelated sessions.
3. Verify from another connection that no test requests or locks remain. Wait for any rollback to finish and compare metrics with the baseline.
4. Once all load has stopped, rerun the table scripts to restore initial data. **This deletes those tables' current data.** Procedures do not need to be recreated unless changed.

`Payload` has a fixed length limit. Deadlock generators and row-blocking procedures append characters; long or repeated runs can eventually cause truncation errors. Reset tables between tests to avoid confusing these errors with contention.

Resetting does not remove lab objects or stop monitoring and its costs. Decommission those resources separately.
