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
