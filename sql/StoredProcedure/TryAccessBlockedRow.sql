CREATE OR ALTER PROCEDURE SalesLT.TryAccessBlockedRow
    @Id INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SET LOCK_TIMEOUT 5000; -- 5 segundos

    BEGIN TRY
        UPDATE SalesLT.LongBlockTest
        SET Payload = Payload + 'Y'
        WHERE Id = @Id;

        PRINT 'Actualización completada sin bloqueo.';
    END TRY
    BEGIN CATCH
        PRINT 'Timeout o bloqueo detectado: ' + ERROR_MESSAGE();
    END CATCH;
END;
