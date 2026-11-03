IF OBJECT_ID('SalesLT.LongBlockTest', 'U') IS NOT NULL
    DROP TABLE SalesLT.LongBlockTest;

CREATE TABLE SalesLT.LongBlockTest (
    Id INT PRIMARY KEY,
    Payload NVARCHAR(200)
);

INSERT INTO SalesLT.LongBlockTest (Id, Payload)
VALUES (1, 'A'), (2, 'B'), (3, 'C');
