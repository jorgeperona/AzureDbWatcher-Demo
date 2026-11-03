SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE SalesLT.GenerateDeadlocksAggressive
    @Loops INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Id1 INT, @Id2 INT;

    WHILE @Loops > 0
    BEGIN
        -- Seleccion aleatoria de dos filas distintas
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

            -- Espera para permitir colision con otra sesion
            WAITFOR DELAY '00:00:05';

            -- Segundo bloqueo fuerte
            UPDATE SalesLT.DeadlockStress WITH (XLOCK, HOLDLOCK)
            SET Payload = Payload + 'B'
            WHERE Id = @Id2;

            COMMIT;
        END TRY
        BEGIN CATCH
            -- Si hay deadlock, se registra y se continua
            IF XACT_STATE() <> 0
                ROLLBACK;

            PRINT 'Deadlock detectado en iteracion ' + CAST(@Loops AS NVARCHAR(10));
        END CATCH;

        SET @Loops = @Loops - 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE SalesLT.GenerateDeadlocksUltra
    @Loops INT = 500
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Id1 INT, @Id2 INT, @Dummy INT;

    WHILE @Loops > 0
    BEGIN
        -- Seleccion aleatoria de dos filas distintas
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

            -- Espera minima para permitir colision
            WAITFOR DELAY '00:00:00.300';

            -- Segundo bloqueo fuerte sobre otra fila
            UPDATE SalesLT.DeadlockUltra WITH (XLOCK, ROWLOCK, HOLDLOCK)
            SET Payload = Payload + 'Y',
                UpdatedAt = GETDATE()
            WHERE Id = @Id2;

            -- Escaneo adicional para aumentar contencion
            SELECT @Dummy = CHECKSUM(t.Payload)
            FROM SalesLT.DeadlockUltra t
            CROSS APPLY (SELECT TOP 1 * FROM SalesLT.DeadlockUltra WITH (UPDLOCK)) ca;

            COMMIT;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0
                ROLLBACK;

            PRINT 'Deadlock detectado en iteracion ' + CAST(@Loops AS NVARCHAR(10));
        END CATCH;

        SET @Loops -= 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE SalesLT.GenerateLongBlock
    @Id INT = 1,
    @HoldSeconds INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Delay VARCHAR(8);

    -- Convertir segundos a formato hh:mm:ss valido
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
GO

CREATE OR ALTER PROCEDURE SalesLT.TableLockAndCpuIoStress
    @Loops INT = 1000
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Dummy BIGINT;

    WHILE @Loops > 0
    BEGIN
        BEGIN TRY
            BEGIN TRAN;

            -- 1) BLOQUEO DE TABLA COMPLETA
            UPDATE t WITH (TABLOCKX)
            SET Payload = LEFT(Payload, 3900) + 'LOCK'
            FROM SalesLT.TableLockStress t;

            -- 2) CARGA DE CPU: funciones hash sobre muchas filas
            SELECT @Dummy = CHECKSUM(Payload) ^ CHECKSUM(CreatedAt)
            FROM SalesLT.TableLockStress WITH (NOLOCK);

            -- 3) CARGA DE IO: lecturas repetidas y joins cruzados
            SELECT TOP 1000 @Dummy = @Dummy ^ CHECKSUM(t1.Payload) ^ CHECKSUM(t2.Payload)
            FROM SalesLT.TableLockStress t1 WITH (NOLOCK)
            CROSS JOIN SalesLT.TableLockStress t2 WITH (NOLOCK);

            COMMIT;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0
                ROLLBACK;
        END CATCH;

        SET @Loops -= 1;
    END
END;
GO

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

        PRINT 'Actualizacion completada sin bloqueo.';
    END TRY
    BEGIN CATCH
        PRINT 'Timeout o bloqueo detectado: ' + ERROR_MESSAGE();
    END CATCH;
END;
GO