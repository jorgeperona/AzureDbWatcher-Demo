/*Create all demo tables for deadlock and blocking stress tests*/

--Create DeadlockStress

IF OBJECT_ID('SalesLT.DeadlockStress', 'U') IS NOT NULL
    DROP TABLE SalesLT.DeadlockStress;

CREATE TABLE SalesLT.DeadlockStress (
    Id INT PRIMARY KEY,
    Payload NVARCHAR(200)
);

INSERT INTO SalesLT.DeadlockStress (Id, Payload)
VALUES (1, 'X'), (2, 'Y'), (3, 'Z'), (4, 'W');

--Create DeadlockUltra
IF OBJECT_ID('SalesLT.DeadlockUltra', 'U') IS NOT NULL
    DROP TABLE SalesLT.DeadlockUltra;

CREATE TABLE SalesLT.DeadlockUltra (
    Id INT PRIMARY KEY,
    Payload NVARCHAR(200),
    UpdatedAt DATETIME
);

INSERT INTO SalesLT.DeadlockUltra (Id, Payload, UpdatedAt)
VALUES (1, 'A', GETDATE()),
       (2, 'B', GETDATE()),
       (3, 'C', GETDATE()),
       (4, 'D', GETDATE()),
       (5, 'E', GETDATE());

--Create LongBlockTest
IF OBJECT_ID('SalesLT.LongBlockTest', 'U') IS NOT NULL
    DROP TABLE SalesLT.LongBlockTest;

CREATE TABLE SalesLT.LongBlockTest (
    Id INT PRIMARY KEY,
    Payload NVARCHAR(200)
);

INSERT INTO SalesLT.LongBlockTest (Id, Payload)
VALUES (1, 'A'), (2, 'B'), (3, 'C');

--Create TableLockStress
IF OBJECT_ID('SalesLT.TableLockStress', 'U') IS NOT NULL
    DROP TABLE SalesLT.TableLockStress;

CREATE TABLE SalesLT.TableLockStress (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Payload NVARCHAR(4000),
    CreatedAt DATETIME
);

-- Rellenamos con bastantes filas para que haya lectura/IO
;WITH N AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM N WHERE n < 5000
)
INSERT INTO SalesLT.TableLockStress (Payload, CreatedAt)
SELECT REPLICATE('X', 4000), DATEADD(SECOND, n, GETDATE())
FROM N
OPTION (MAXRECURSION 5000);
