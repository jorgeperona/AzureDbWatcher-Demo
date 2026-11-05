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

            THROW;
        END CATCH;

        SET @Loops -= 1;
    END
END;
