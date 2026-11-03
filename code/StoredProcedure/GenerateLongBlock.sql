CREATE OR ALTER PROCEDURE SalesLT.GenerateLongBlock
    @Id INT = 1,
    @HoldSeconds INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Delay VARCHAR(8);

    -- Convertir segundos a formato hh:mm:ss válido
    SELECT @Delay =
        RIGHT('00' + CAST(@HoldSeconds / 3600 AS VARCHAR(2)), 2) + ':' +
        RIGHT('00' + CAST((@HoldSeconds % 3600) / 60 AS VARCHAR(2)), 2) + ':' +
        RIGHT('00' + CAST(@HoldSeconds % 60 AS VARCHAR(2)), 2);

    BEGIN TRAN;

    -- Bloqueo exclusivo real
    UPDATE SalesLT.LongBlockTest WITH (XLOCK, ROWLOCK)
    SET Payload = Payload + 'X'
    WHERE Id = @Id;

    -- Mantener el bloqueo
    WAITFOR DELAY @Delay;

    COMMIT;
END;
