CREATE OR ALTER PROCEDURE SalesLT.GenerateDeadlocksUltra
    @Loops INT = 500
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Id1 INT, @Id2 INT, @Dummy INT;

    WHILE @Loops > 0
    BEGIN
        -- Selección aleatoria de dos filas distintas
        SELECT @Id1 = ABS(CHECKSUM(NEWID())) % 5 + 1;
        SELECT @Id2 = ABS(CHECKSUM(NEWID())) % 5 + 1;

        WHILE @Id1 = @Id2
            SELECT @Id2 = ABS(CHECKSUM(NEWID())) % 5 + 1;

        BEGIN TRY
            BEGIN TRAN;

            -- Bloqueo fuerte sobre la primera fila
            UPDATE SalesLT.DeadlockUltra WITH (XLOCK, ROWLOCK, HOLDLOCK)
            SET Payload = Payload + 'X',
                UpdatedAt = GETDATE()
            WHERE Id = @Id1;

            -- Lectura pesada para generar IO
            SELECT TOP 1000 @Dummy = CHECKSUM(Payload)
            FROM SalesLT.DeadlockUltra WITH (READPAST);

            -- Espera mínima para permitir colisión
            WAITFOR DELAY '00:00:00.300';

            -- Segundo bloqueo fuerte sobre otra fila
            UPDATE SalesLT.DeadlockUltra WITH (XLOCK, ROWLOCK, HOLDLOCK)
            SET Payload = Payload + 'Y',
                UpdatedAt = GETDATE()
            WHERE Id = @Id2;

            -- Escaneo adicional para aumentar contención
            SELECT @Dummy = CHECKSUM(t.Payload)
            FROM SalesLT.DeadlockUltra t
            CROSS APPLY (SELECT TOP 1 * FROM SalesLT.DeadlockUltra WITH (UPDLOCK)) ca;

            COMMIT;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0
                ROLLBACK;

            PRINT 'Deadlock detectado en iteración ' + CAST(@Loops AS NVARCHAR(10));
        END CATCH;

        SET @Loops -= 1;
    END
END;
