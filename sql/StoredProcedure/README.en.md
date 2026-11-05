# Stress procedures

[Español](README.md) | [Lab guide](../README.en.md)

Create the [required tables](../CreateTable/README.en.md) first. Run [Create_All_StoredProcedures.sql](Create_All_StoredProcedures.sql) to install all five procedures, or use their individual files. All use `CREATE OR ALTER PROCEDURE`: rerunning updates their definitions without resetting data.

The combined script uses `GO` separators, interpreted by clients such as SSMS and the MSSQL extension for VS Code, not by the T-SQL engine. Do not send the file as a single statement through a driver that does not process those separators.

## Catalog

All objects belong to the `SalesLT` schema.

| File / procedure | Parameters and defaults | Table | Behavior |
|---|---|---|---|
| [GenerateDeadlocksAggressive.sql](GenerateDeadlocksAggressive.sql) | `@Loops INT = 100` | `DeadlockStress` | Updates two distinct random rows with `XLOCK, HOLDLOCK`; waits 5 s between updates |
| [GenerateDeadlocksUltra.sql](GenerateDeadlocksUltra.sql) | `@Loops INT = 500` | `DeadlockUltra` | Uses `XLOCK, ROWLOCK, HOLDLOCK`, waits 300 ms, and adds reads with `READPAST` and `UPDLOCK` |
| [GenerateLongBlock.sql](GenerateLongBlock.sql) | `@Id INT = 1`, `@HoldSeconds INT = 30` | `LongBlockTest` | Updates a row with `XLOCK, ROWLOCK` and keeps the transaction open during the delay |
| [TryAccessBlockedRow.sql](TryAccessBlockedRow.sql) | `@Id INT = 1` | `LongBlockTest` | Attempts a row update with `LOCK_TIMEOUT 5000` and reports the result through `PRINT` |
| [TableLockAndCpuIoStress.sql](TableLockAndCpuIoStress.sql) | `@Loops INT = 1000` | `TableLockStress` | Updates the entire table with `TABLOCKX`, calculates checksums, and performs a cross join limited by `TOP 1000` |

## Recommended usage

```sql
-- Run concurrently in two or more connections:
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 10;

-- Alternative variant, also with concurrent connections:
EXEC SalesLT.GenerateDeadlocksUltra @Loops = 20;

-- Connection A:
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 30;
-- Connection B, while A holds the lock:
EXEC SalesLT.TryAccessBlockedRow @Id = 1;

-- Separate table-load test:
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 10;
```

Run each scenario separately and without outer transactions. Deadlocks require concurrency and are not guaranteed. To observe a timeout, both connections must use the same `@Id`, and the second must start during the first connection's delay.

## Parameters and limitations

- Start with a small positive `@Loops`. Zero or negative values skip the loop.
- For `LongBlockTest`, use an existing `@Id`, from 1 to 3; procedures do not validate whether the row exists.
- Use `@HoldSeconds` between 0 and 86399, compatible with the `hh:mm:ss` delay format; input is not validated. Start with 30 or 60 seconds.
- Blocking and available capacity can extend calls. A wait does not by itself imply CPU consumption.
- Deadlock tables contain only four or five rows; Ultra's additional reads do not guarantee high I/O load.
- Lock hint behavior also depends on isolation and database settings; inspect actual errors if a call does not produce the expected effect.
- Ultra bounds `Payload` to 200 characters for recurring runs and combines `READPAST` with `READCOMMITTEDLOCK` to support `READ_COMMITTED_SNAPSHOT` databases. Aggressive and LongBlockTest still grow their payloads: reset their tables between tests.

## Error interpretation and stopping

- Ultra rolls back and continues only for error 1205, rethrowing other errors to the runner. Aggressive retains its original behavior: it prints `Deadlock detectado` for any caught error and continues. Verify deadlocks using captured events.
- `TryAccessBlockedRow` catches errors and prints their message without rethrowing. A lock timeout (normally error 1222) is not a deadlock.
- `TableLockAndCpuIoStress` rolls back and rethrows errors, stopping the call and exposing failures to the runner.
- `GenerateLongBlock` has no `TRY/CATCH`. An error or cancellation can leave an open transaction.

After cancellation, check `@@TRANCOUNT` and `XACT_STATE()` in every affected connection and roll back remaining lab transactions. Follow the [stop and reset steps](../README.en.md#5-stop-and-reset).
