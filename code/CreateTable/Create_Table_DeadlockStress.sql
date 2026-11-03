IF OBJECT_ID('SalesLT.DeadlockStress', 'U') IS NOT NULL
    DROP TABLE SalesLT.DeadlockStress;

CREATE TABLE SalesLT.DeadlockStress (
    Id INT PRIMARY KEY,
    Payload NVARCHAR(200)
);

INSERT INTO SalesLT.DeadlockStress (Id, Payload)
VALUES (1, 'X'), (2, 'Y'), (3, 'Z'), (4, 'W');
