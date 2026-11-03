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
