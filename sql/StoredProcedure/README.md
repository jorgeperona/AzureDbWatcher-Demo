# Procedimientos de estrés

[English](README.en.md) | [Guía del laboratorio](../README.md)

Crea primero las [tablas necesarias](../CreateTable/README.md). Ejecuta [Create_All_StoredProcedures.sql](Create_All_StoredProcedures.sql) para instalar los cinco procedimientos o utiliza sus ficheros individuales. Todos usan `CREATE OR ALTER PROCEDURE`: una nueva ejecución actualiza su definición, sin restablecer los datos.

El combinado utiliza separadores `GO`, interpretados por clientes como SSMS y la extensión MSSQL de VS Code, no por el motor T-SQL. No envíes el fichero como una única instrucción mediante un controlador que no procese esos separadores.

## Catálogo

Todos los objetos pertenecen al esquema `SalesLT`.

| Fichero / procedimiento | Parámetros y valores predeterminados | Tabla | Comportamiento |
|---|---|---|---|
| [GenerateDeadlocksAggressive.sql](GenerateDeadlocksAggressive.sql) | `@Loops INT = 100` | `DeadlockStress` | Actualiza dos filas aleatorias distintas con `XLOCK, HOLDLOCK`; espera 5 s entre actualizaciones |
| [GenerateDeadlocksUltra.sql](GenerateDeadlocksUltra.sql) | `@Loops INT = 500` | `DeadlockUltra` | Usa `XLOCK, ROWLOCK, HOLDLOCK`, espera 300 ms y añade lecturas con `READPAST` y `UPDLOCK` |
| [GenerateLongBlock.sql](GenerateLongBlock.sql) | `@Id INT = 1`, `@HoldSeconds INT = 30` | `LongBlockTest` | Actualiza una fila con `XLOCK, ROWLOCK` y mantiene la transacción durante la espera |
| [TryAccessBlockedRow.sql](TryAccessBlockedRow.sql) | `@Id INT = 1` | `LongBlockTest` | Intenta actualizar una fila con `LOCK_TIMEOUT 5000` y muestra el resultado con `PRINT` |
| [TableLockAndCpuIoStress.sql](TableLockAndCpuIoStress.sql) | `@Loops INT = 1000` | `TableLockStress` | Actualiza toda la tabla con `TABLOCKX`, calcula checksums y hace un producto cruzado limitado por `TOP 1000` |

## Uso recomendado

```sql
-- Ejecutar simultáneamente en dos o más conexiones:
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 10;

-- Variante alternativa, también con conexiones concurrentes:
EXEC SalesLT.GenerateDeadlocksUltra @Loops = 20;

-- Conexión A:
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 30;
-- Conexión B, mientras A mantiene el bloqueo:
EXEC SalesLT.TryAccessBlockedRow @Id = 1;

-- Prueba independiente de carga de tabla:
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 10;
```

Ejecuta cada escenario por separado y sin transacciones externas. Los deadlocks requieren concurrencia y no están garantizados. Para observar el timeout, ambas conexiones deben usar el mismo `@Id` y la segunda debe empezar durante la espera de la primera.

## Parámetros y limitaciones

- Usa `@Loops` positivo y pequeño al empezar. Los valores cero o negativos no ejecutan el bucle.
- Para `LongBlockTest`, usa un `@Id` existente, del 1 al 3; los procedimientos no validan si la fila existe.
- Usa `@HoldSeconds` entre 0 y 86399, compatible con el formato de espera `hh:mm:ss`; no hay validación de entrada. Empieza con 30 o 60 segundos.
- Los bloqueos y la capacidad disponible pueden alargar las llamadas. Una espera no equivale por sí misma a consumo de CPU.
- Las tablas de deadlock solo tienen cuatro o cinco filas; las lecturas adicionales de Ultra no garantizan carga elevada de E/S.
- El efecto de las sugerencias de bloqueo depende también del aislamiento y la configuración de la base de datos; revisa los errores reales si una llamada no produce el efecto esperado.
- Los `Payload NVARCHAR(200)` crecen con las actualizaciones y pueden alcanzar su límite. Restablece las tablas entre pruebas.

## Interpretación de errores y parada

- Los generadores de deadlocks hacen rollback de la transacción activa en su `CATCH` y continúan, pero imprimen `Deadlock detectado` para cualquier error capturado. Confirma el error 1205 en la captura de eventos; no cuentes esos mensajes como deadlocks verificados.
- `TryAccessBlockedRow` captura errores y muestra su mensaje, sin relanzarlos. Un timeout de bloqueo (normalmente error 1222) no es un deadlock.
- `TableLockAndCpuIoStress` hace rollback en su `CATCH`, pero no muestra ni relanza el error. Que termine no demuestra que todas las iteraciones hayan tenido éxito.
- `GenerateLongBlock` no tiene `TRY/CATCH`. Un error o cancelación puede dejar una transacción abierta.

Después de cancelar, comprueba `@@TRANCOUNT` y `XACT_STATE()` en cada conexión afectada y revierte las transacciones del laboratorio que sigan abiertas. Sigue los pasos de [parada y restablecimiento](../README.md#5-detener-y-restablecer).
