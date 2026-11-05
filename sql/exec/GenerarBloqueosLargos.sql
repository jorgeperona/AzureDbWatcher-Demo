-- Genera bloqueos largos
-- Ejecutar en Ventana de Consulta 1
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 60;
-- Ejecutar en Ventana de Consulta 2 o ejecutar el script a continuación.
EXEC SalesLT.TryAccessBlockedRow @Id = 1;


-- En la ventana 2, mientras la query 1 mantiene el bloqueo, puedes repetir la llamada con un WHILE. Este ejemplo limita cada espera a 3 segundos y realiza 15 intentos:
SET LOCK_TIMEOUT 3000; -- Espera máxima por intento: 3 segundos

DECLARE @i int = 1;

WHILE @i <= 15
BEGIN
    BEGIN TRY
        EXEC SalesLT.TryAccessBlockedRow @Id = 1;
        PRINT CONCAT('Intento ', @i, ': terminó sin error.');
    END TRY
    BEGIN CATCH
        PRINT CONCAT(
            'Intento ', @i,
            ': error ', ERROR_NUMBER(),
            ' - ', ERROR_MESSAGE()
        );
    END CATCH;

    SET @i += 1;
    WAITFOR DELAY '00:00:01';
END;

SET LOCK_TIMEOUT -1; -- Restaura la espera predeterminada
