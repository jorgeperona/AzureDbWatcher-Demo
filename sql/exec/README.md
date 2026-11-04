# Ejecución y diagnóstico

[English](README.en.md) | [Guía del laboratorio](../README.md)

Antes de ejecutar carga, prepara las [tablas](../CreateTable/README.md) y los [procedimientos](../StoredProcedure/README.md), confirma la base de datos de destino y configura la monitorización.

## Ficheros

### [Run_All_StressProcedures.sql](Run_All_StressProcedures.sql)

Lanza estas llamadas **en secuencia en una única conexión**, mostrando mensajes de inicio y fin:

| Orden | Procedimiento de `SalesLT` | Argumentos |
|---:|---|---|
| 1 | `GenerateDeadlocksAggressive` | `@Loops = 100` |
| 2 | `GenerateDeadlocksUltra` | `@Loops = 500` |
| 3 | `GenerateLongBlock` | `@Id = 1, @HoldSeconds = 30` |
| 4 | `TryAccessBlockedRow` | `@Id = 1` |
| 5 | `TableLockAndCpuIoStress` | `@Loops = 1000` |

No crea sesiones adicionales. Sin otra conexión concurrente, los generadores no demuestran deadlocks entre sesiones, y el acceso a la fila ocurre después del `COMMIT` del bloqueo prolongado.

Es una ejecución potencialmente larga: solo las esperas de Aggressive suman unos 500 segundos si las iteraciones llegan a ellas, antes de considerar los demás pasos y la contención. Empieza con llamadas individuales y menos iteraciones. Los mensajes de fin no garantizan ausencia de errores capturados internamente.

### [bloqueos.sql](bloqueos.sql)

Es un cuaderno de consultas y ejemplos manuales, **no un lote listo para ejecutar**:

- Sus encabezados `#` y `##` no son comentarios T-SQL válidos. Copia únicamente la consulta necesaria o conviértelos en comentarios `--` antes de ejecutarlos.
- Sustituye `tu_usuario` por el login real al filtrar `sys.dm_exec_sessions`.
- La consulta a `sys.event_log` no es un diagnóstico genérico de deadlocks. Esa vista depende de la plataforma, se consulta en `master` de Azure SQL Database y sus columnas no coinciden con `event_timestamp` usado en el fichero. No la ejecutes sin adaptarla; usa la captura de eventos/gráficos de deadlock disponible en tu entorno.
- El filtro `session_id > 50` de la consulta de solicitudes es orientativo, no identifica por sí mismo las sesiones de la prueba.
- Incluye ejemplos con 500 y 1000 iteraciones para deadlocks y **100000** para carga de tabla: no los uses como punto de partida.

## Pruebas con conexiones independientes

Ejecuta solo el bloque del escenario elegido, no todos los ejemplos de una vez.

### Bloqueo y timeout

Conexión A:

```sql
SELECT @@SPID AS SessionA;
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 60;
```

Conexión B, antes de que termine A:

```sql
SELECT @@SPID AS SessionB;
EXEC SalesLT.TryAccessBlockedRow @Id = 1;
```

Se espera un mensaje de timeout en B tras aproximadamente cinco segundos. Si A ya terminó o se eligieron filas distintas, B puede completar sin bloqueo.

### Deadlocks y carga de tabla

Ejecuta el mismo generador en al menos dos conexiones simultáneamente:

```sql
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 10;
```

Como alternativa, prueba `GenerateDeadlocksUltra @Loops = 20` en conexiones concurrentes. Los deadlocks son probabilísticos; verifica eventos, no solo mensajes.

Para una prueba independiente de bloqueo de tabla y carga:

```sql
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 10;
```

## Diagnóstico durante la carga

En una conexión adicional a la misma base de datos, registra primero los identificadores de las sesiones de prueba. Con permisos suficientes:

```sql
SELECT session_id, login_name, status, cpu_time, reads, writes
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
  AND session_id <> @@SPID;

SELECT session_id, status, blocking_session_id,
       wait_type, wait_time, wait_resource
FROM sys.dm_exec_requests
WHERE session_id <> @@SPID;
```

Estas consultas pueden mostrar otras sesiones: correlaciona sus identificadores con los de la prueba. La visibilidad depende de los permisos y del ámbito de la plataforma. `sys.dm_exec_requests` muestra solicitudes actuales, no un historial de deadlocks; una sesión inactiva con transacción abierta puede no aparecer allí.

Compara los resultados con CPU, E/S de datos, E/S del log y esperas de la monitorización. Si el panel no refleja un evento, revisa muestreo, ingestión y configuración antes de concluir que la prueba no generó carga.

## Finalización

Cancela o deja terminar todas las conexiones de carga; comprueba y revierte las transacciones del laboratorio abiertas en cada conexión. Espera a que desaparezcan los bloqueos y termine cualquier rollback antes de restablecer tablas. Consulta las [instrucciones completas de parada](../README.md#5-detener-y-restablecer).
