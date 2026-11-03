CREATE OR ALTER PROCEDURE SalesLT.GenerateDeadlocksAggressive
    @Loops INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Id1 INT, @Id2 INT;

    WHILE @Loops > 0
    BEGIN
        -- Selección aleatoria de dos filas distintas
        SELECT @Id1 = ABS(CHECKSUM(NEWID())) % 4 + 1;
        SELECT @Id2 = ABS(CHECKSUM(NEWID())) % 4 + 1;

        WHILE @Id1 = @Id2
            SELECT @Id2 = ABS(CHECKSUM(NEWID())) % 4 + 1;

        BEGIN TRY
            BEGIN TRAN;

            -- Primer bloqueo fuerte
            UPDATE SalesLT.DeadlockStress WITH (XLOCK, HOLDLOCK)
            SET Payload = Payload + 'A'
            WHERE Id = @Id1;

            -- Espera para permitir colisión con otra sesión
            WAITFOR DELAY '00:00:05';

            -- Segundo bloqueo fuerte
            UPDATE SalesLT.DeadlockStress WITH (XLOCK, HOLDLOCK)
            SET Payload = Payload + 'B'
            WHERE Id = @Id2;

            COMMIT;
        END TRY
        BEGIN CATCH
            -- Si hay deadlock, se registra y se continúa
            IF XACT_STATE() <> 0
                ROLLBACK;

            PRINT 'Deadlock detectado en iteración ' + CAST(@Loops AS NVARCHAR(10));
        END CATCH;

        SET @Loops = @Loops - 1;
    END
END;
