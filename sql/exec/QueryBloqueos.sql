-- Ver sesiones activas
DECLARE @login_name_activo sysname = N'jorgeperona@sbsconsulting.es';
SELECT session_id, login_name, status, cpu_time, reads, writes
FROM sys.dm_exec_sessions
WHERE login_name = @login_name_activo
ORDER BY session_id;

-- Ver bloqueos en tiempo real
SELECT
    r.session_id,
    r.status,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.wait_resource
FROM sys.dm_exec_requests r
WHERE r.session_id > 50;

-- Relacionar sesiones con sus solicitudes en curso y bloqueos
DECLARE @login_name sysname = N'jorgeperona@sbsconsulting.es';
SELECT
    s.session_id,
    s.login_name,
    s.status AS session_status,
    s.cpu_time,
    s.reads,
    s.writes,
    r.status AS request_status,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.wait_resource
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id
WHERE s.login_name = @login_name
  AND s.session_id > 50
ORDER BY s.session_id;


--------------


-- Sesiones que están bloqueadas y quién las bloquea
SELECT
    r.session_id AS sesion_bloqueada,
    r.blocking_session_id AS sesion_bloqueadora,
    s.login_name,
    r.status,
    r.wait_type,
    r.wait_time / 1000.0 AS espera_segundos,
    r.wait_resource,
    txt.text AS consulta
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s
    ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS txt
WHERE r.blocking_session_id <> 0;

-- Para revisar los bloqueos de esas sesiones

SELECT
    l.request_session_id AS session_id,
    s.login_name,
    l.resource_type,
    l.request_mode,
    l.request_status,
    l.resource_description
FROM sys.dm_tran_locks AS l
LEFT JOIN sys.dm_exec_sessions AS s
    ON s.session_id = l.request_session_id
WHERE l.resource_database_id = DB_ID()
ORDER BY l.request_session_id, l.request_status;