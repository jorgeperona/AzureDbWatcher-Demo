# Demo tables

[Español](README.md) | [Lab guide](../README.en.md)

These scripts create and seed the tables used by the stress procedures. The `SalesLT` schema must already exist.

> Each script drops its corresponding table if it exists. Existing data is lost. Stop all tests before creating or resetting tables.

## Files and initial data

| File | Table in `SalesLT` | Rows | Purpose |
|---|---|---:|---|
| [Create_All_DemoTables.sql](Create_All_DemoTables.sql) | All four tables below | 5012 total | Full setup |
| [Create_Table_DeadlockStress.sql](Create_Table_DeadlockStress.sql) | `DeadlockStress` | 4, Id 1–4 | Deadlocks with `GenerateDeadlocksAggressive` |
| [Create_Table_DeadlockUltra.sql](Create_Table_DeadlockUltra.sql) | `DeadlockUltra` | 5, Id 1–5 | Deadlocks with `GenerateDeadlocksUltra` |
| [Create_Table_LongBlockTest.sql](Create_Table_LongBlockTest.sql) | `LongBlockTest` | 3, Id 1–3 | Long blocking and concurrent access |
| [Create_Table_TableLockStress.sql](Create_Table_TableLockStress.sql) | `TableLockStress` | 5000 | Table locking and CPU/I/O load |

The first three tables have `Id INT PRIMARY KEY` and `Payload NVARCHAR(200)`. `DeadlockUltra` adds `UpdatedAt DATETIME`. `TableLockStress` uses an identity `Id`, `Payload NVARCHAR(4000)`, and `CreatedAt DATETIME`; a recursive CTE seeds it with 4000-character strings.

## Execution

1. Connect to the lab database and confirm the target with `SELECT DB_NAME();`.
2. Verify that `SalesLT` exists and that you have permission to create and drop tables.
3. Run **either the combined script or the required individual scripts**, not both: the combined script already includes all four definitions.
4. Verify the listed row counts before [creating procedures](../StoredProcedure/README.en.md).

The four tables have no dependencies on each other. For long blocking only, create `LongBlockTest` and its two associated procedures.

## Reset

Rerun the affected table's script after stopping workloads and resolving open transactions. This restores its initial data; existing procedures remain in place.

Deadlock and row-blocking procedures append characters to `Payload`. Reset data between tests to avoid truncation errors when reaching the 200-character limit.
