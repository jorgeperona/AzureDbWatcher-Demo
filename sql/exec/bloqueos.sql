##QUERYS VARIAS

# Ver lod Deadlocks
SELECT *
FROM sys.event_log
WHERE event_type = 'deadlock'
ORDER BY event_timestamp DESC;

#Ver sesiones activas
SELECT session_id, login_name, status, cpu_time, reads, writes
FROM sys.dm_exec_sessions
WHERE login_name = 'tu_usuario'
ORDER BY session_id;

# Ver Bloqueos en tiemo real
SELECT
    r.session_id,
    r.status,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.wait_resource
FROM sys.dm_exec_requests r
WHERE r.session_id > 50;

## BLOQUEOS Y DEADLOCKS
## Genera DeadLocks + Carga CPU + Aumento de LogIO y IO
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 500;

## DeadLocks + Carga CPU + Aumento de LogIO y IO - Modo Agresivo
EXEC SalesLT.GenerateDeadlocksUltra @Loops = 1000;

## Genera Bloqueos largos
#Ejecutar en Ventana de Consulta 1
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 60;
# Ejecutar en Ventana de Consulta 2
EXEC SalesLT.TryAccessBlockedRow @Id = 1;

## Lock Table and CPU
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 100000;