# Execution and diagnostics

[Español](README.md) | [Lab guide](../README.en.md)

Before generating load, prepare the [tables](../CreateTable/README.en.md) and [procedures](../StoredProcedure/README.en.md), confirm the target database, and configure monitoring.

To repeat aggressive load every two hours without an open client, see the
[Elastic Jobs setup](../elastic-jobs/README.en.md): two deadlock sessions and one
CPU/I/O session per database, without overlapping cycles and initially disabled.

## Files

### [Run_All_StressProcedures.sql](Run_All_StressProcedures.sql)

Runs these calls **sequentially in a single connection**, printing start and end messages:

| Order | Procedure in `SalesLT` | Arguments |
|---:|---|---|
| 1 | `GenerateDeadlocksAggressive` | `@Loops = 100` |
| 2 | `GenerateDeadlocksUltra` | `@Loops = 500` |
| 3 | `GenerateLongBlock` | `@Id = 1, @HoldSeconds = 30` |
| 4 | `TryAccessBlockedRow` | `@Id = 1` |
| 5 | `TableLockAndCpuIoStress` | `@Loops = 1000` |

It does not create additional sessions. Without another concurrent connection, the generators do not demonstrate inter-session deadlocks, and row access occurs after the long-blocking call's `COMMIT`.

This can be a long run: Aggressive's delays alone total about 500 seconds if iterations reach them, before other steps and contention. Start with individual calls and fewer iterations. End messages do not guarantee the absence of internally caught errors.

### [bloqueos.sql](bloqueos.sql)

This is a collection of queries and manual examples, **not an executable batch**. Select only the block you need; don't run the load examples together:

- Replace `tu_usuario` with the actual login when filtering `sys.dm_exec_sessions`.
- In Azure SQL Database, `sys.event_log` records connections and connection failures, not deadlocks. Use the deadlock graphs/events captured by your platform's tooling.
- The requests query's `session_id > 50` filter is only a rough filter, not an identifier of test sessions.
- Examples use 500 and 1000 deadlock iterations and **100000** table-load iterations: do not use these as starting values.

## Tests with independent connections

Run only the block for your chosen scenario, not all examples at once.

### Blocking and timeout

Connection A:

```sql
SELECT @@SPID AS SessionA;
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 60;
```

Connection B, before A finishes:

```sql
SELECT @@SPID AS SessionB;
EXEC SalesLT.TryAccessBlockedRow @Id = 1;
```

B should print a timeout message after approximately five seconds. If A has already finished or different rows were selected, B may complete without blocking.

### Deadlocks and table load

Run the same generator in at least two simultaneous connections:

```sql
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 10;
```

Alternatively, try `GenerateDeadlocksUltra @Loops = 20` in concurrent connections. Deadlocks are probabilistic; verify events, not just messages.

For a separate table-locking and load test:

```sql
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 10;
```

## Diagnostics during load

In an additional connection to the same database, first record the test session IDs. With sufficient permissions:

```sql
SELECT session_id, login_name, status, cpu_time, reads, writes
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
  AND session_id <> @@SPID;

SELECT session_id, status, blocking_session_id,
       wait_type, wait_time, wait_resource
FROM sys.dm_exec_requests
WHERE session_id <> @@SPID;
```

These queries may show other sessions: correlate IDs with your test. Visibility depends on permissions and platform scope. `sys.dm_exec_requests` shows current requests, not deadlock history; an idle session with an open transaction may not appear there.

Compare results with monitoring CPU, data I/O, log I/O, and waits. If a dashboard misses an event, check sampling, ingestion, and configuration before concluding that the test generated no load.

## Finishing

Cancel or let all load connections finish; check and roll back open lab transactions in each connection. Wait for blocking to clear and any rollback to finish before resetting tables. See the [complete stop instructions](../README.en.md#5-stop-and-reset).
