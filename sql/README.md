# Laboratorio de estrés SQL

[English](README.en.md)

Laboratorio para provocar contención, bloqueos prolongados, deadlocks y carga de CPU/E/S en una base de datos de pruebas, y observar la respuesta de la monitorización, por ejemplo, Azure SQL Database watcher. Estos scripts no despliegan recursos ni configuran la monitorización. La carpeta `loadtesting` queda fuera de esta guía.

> **Solo para un entorno de laboratorio aislado.** Los scripts modifican datos, pueden consumir recursos y generar costes. Los scripts de creación de tablas eliminan las tablas de demostración existentes y sus datos. No ejecutarlos en producción.

## Requisitos

- Una base de datos de pruebas en Azure SQL Database o SQL Server compatible con `CREATE OR ALTER PROCEDURE`.
- Un cliente como SQL Server Management Studio (SSMS) o la extensión MSSQL de VS Code. El script combinado de procedimientos requiere un cliente que interprete `GO`.
- Permisos para crear tablas y procedimientos en el esquema `SalesLT`, eliminar las tablas de demostración y ejecutar los procedimientos. Consultar las vistas de diagnóstico requiere permisos adicionales según plataforma y versión.
- Varias conexiones independientes a la **misma base de datos**. No basta con ejecutar varias instrucciones en una sola sesión.
- Monitorización configurada previamente, con acceso a métricas, sesiones, esperas y, si está disponible, captura de deadlocks.

## 1. Preparar la base de datos

Confirma el destino antes de ejecutar scripts destructivos:

```sql
SELECT DB_NAME() AS DatabaseName, @@SPID AS SessionId;
```

Los scripts usan `SalesLT`, pero no lo crean. Si no existe, créalo con una identidad autorizada:

```sql
IF SCHEMA_ID(N'SalesLT') IS NULL
    EXEC(N'CREATE SCHEMA SalesLT AUTHORIZATION dbo;');
```

1. Ejecuta [Create_All_DemoTables.sql](CreateTable/Create_All_DemoTables.sql).
2. Ejecuta [Create_All_StoredProcedures.sql](StoredProcedure/Create_All_StoredProcedures.sql).
3. Comprueba los datos iniciales:

```sql
SELECT 'DeadlockStress' AS TableName, COUNT(*) AS RowCount FROM SalesLT.DeadlockStress
UNION ALL
SELECT 'DeadlockUltra', COUNT(*) FROM SalesLT.DeadlockUltra
UNION ALL
SELECT 'LongBlockTest', COUNT(*) FROM SalesLT.LongBlockTest
UNION ALL
SELECT 'TableLockStress', COUNT(*) FROM SalesLT.TableLockStress;
```

Los recuentos esperados son **4, 5, 3 y 5000**. También puedes preparar escenarios individuales; consulta las guías de [tablas](CreateTable/README.md) y [procedimientos](StoredProcedure/README.md).

## 2. Registrar una línea base

Antes de generar carga, registra la hora, CPU, E/S de datos, E/S del log, sesiones y esperas. Anota el número de conexiones y los parámetros de cada prueba. Abre otra conexión para diagnóstico y mantén visible la monitorización.

## 3. Ejecutar los escenarios

Empieza con pocas iteraciones y prueba cada escenario por separado. Ejecuta los ejemplos sin una transacción externa.

### Bloqueo prolongado y timeout

En la conexión A:

```sql
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 30;
```

Mientras A sigue ejecutándose, ejecuta en la conexión B:

```sql
EXEC SalesLT.TryAccessBlockedRow @Id = 1;
```

A conserva un bloqueo exclusivo hasta el `COMMIT`. B intenta actualizar la misma fila y normalmente muestra un mensaje de timeout tras unos cinco segundos. Después de terminar A, repite B para observar la actualización sin bloqueo. En una tercera conexión observa las sesiones bloqueadas y esperas `LCK_M_*`.

### Deadlocks

Ejecuta esta llamada simultáneamente en dos o más conexiones:

```sql
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 10;
```

Para probar la variante de mayor contención, usa en varias conexiones:

```sql
EXEC SalesLT.GenerateDeadlocksUltra @Loops = 20;
```

Los procedimientos actualizan pares aleatorios de filas; la concurrencia favorece ciclos de bloqueo, pero **no garantiza deadlocks en cada ejecución**. La variante Aggressive espera cinco segundos por iteración; Ultra espera 300 ms y añade lecturas. El tiempo total depende también de bloqueos y recursos disponibles.

### Bloqueo de tabla y carga de CPU/E/S

```sql
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 10;
```

Actualiza las 5000 filas con `TABLOCKX` y realiza cálculos y lecturas adicionales. Aumenta las iteraciones gradualmente si la carga es insuficiente. Con varias sesiones sobre esta tabla puede observarse contención.

No se garantiza saturación ni E/S física elevada: influyen la caché, los planes de ejecución y la capacidad de la base de datos. El producto cruzado del procedimiento está limitado por `TOP 1000`.

### Ejecutor global

[Run_All_StressProcedures.sql](exec/Run_All_StressProcedures.sql) ejecuta todos los procedimientos **en secuencia**, con 100, 500 y 1000 iteraciones en los generadores correspondientes. No crea conexiones concurrentes. Por sí solo no demuestra deadlocks entre sesiones ni el timeout del escenario anterior, porque intenta acceder a la fila después de que termine el bloqueo. Consulta la [guía de ejecución](exec/README.md).

## 4. Observar los resultados

Durante las pruebas, desde otra conexión a la base de datos:

```sql
SELECT session_id, status, blocking_session_id,
       wait_type, wait_time, wait_resource
FROM sys.dm_exec_requests
WHERE session_id <> @@SPID
ORDER BY blocking_session_id DESC, session_id;
```

- Correlaciona las horas y los identificadores de sesión con bloqueos, esperas, CPU, E/S de datos y del log.
- Un timeout de bloqueo no es un deadlock. Confirma los deadlocks con los eventos o gráficos de deadlock disponibles en tu plataforma.
- Ten en cuenta los intervalos de muestreo e ingestión: un evento corto puede no aparecer en una captura periódica.
- Los mensajes `Deadlock detectado` no son prueba suficiente: ambos generadores muestran ese texto para **cualquier error capturado**, no solo el error 1205. El procedimiento de carga de tabla no informa los errores que captura.

[bloqueos.sql](exec/bloqueos.sql) contiene apuntes, no un lote listo para ejecutar: usa encabezados `#` que no son comentarios T-SQL válidos, un usuario de ejemplo y una consulta a `sys.event_log` que no debe tratarse como un historial portable de deadlocks. Consulta las advertencias de la [guía de ejecución](exec/README.md).

## 5. Detener y restablecer

1. Deja terminar las llamadas o cancela **cada conexión** que genera carga.
2. Tras cancelar o recibir un error, comprueba el estado en esa misma conexión:

   ```sql
   SELECT @@TRANCOUNT AS OpenTransactions, XACT_STATE() AS TransactionState;
   -- Solo si queda una transacción del laboratorio abierta:
   IF @@TRANCOUNT > 0
       ROLLBACK;
   ```

   Cancelar no garantiza un rollback inmediato. Si pierdes la conexión, un administrador debe comprobar las sesiones afectadas; no finalices sesiones ajenas.
3. Verifica desde otra conexión que no queden solicitudes o bloqueos de la prueba. Espera a que termine cualquier rollback y compara las métricas con la línea base.
4. Con todas las cargas detenidas, vuelve a ejecutar los scripts de tablas para recuperar los datos iniciales. **Esto elimina los datos actuales de esas tablas.** No es necesario recrear los procedimientos si no han cambiado.

`Payload` tiene longitud limitada. Los generadores de deadlocks y los procedimientos de bloqueo de fila añaden caracteres; las ejecuciones prolongadas o repetidas pueden acabar en errores de truncamiento. Restablece las tablas entre pruebas para no confundir esos errores con contención.

El restablecimiento no elimina los objetos del laboratorio ni detiene la monitorización o sus costes. La retirada de esos recursos se gestiona por separado.
