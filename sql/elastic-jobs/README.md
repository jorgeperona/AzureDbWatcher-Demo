# Estrés recurrente cada dos horas con Elastic Jobs

[English](README.en.md) | [Laboratorio SQL](../README.md)

**Preparación solamente: no se han creado recursos ni activado carga en Azure.**
Los scripts crean cuatro jobs con sus programaciones **deshabilitadas**. No necesitan
que el ordenador, VS Code o una sesión SQL permanezcan abiertos.

## Destinos y ciclo

| Servidor | Base de datos |
|---|---|
| `datasaturday01.database.windows.net` | `datasaturdaydb01` |
| `datasaturday02.database.windows.net` | `datasaturdaydb02` |

Cada ciclo lanza tres jobs independientes contra **ambas** bases:

| Job | Llamada por base de datos |
|---|---|
| `DemoStress-Deadlocks-A` | `EXEC SalesLT.GenerateDeadlocksUltra @Loops = 1000;` |
| `DemoStress-Deadlocks-B` | `EXEC SalesLT.GenerateDeadlocksUltra @Loops = 1000;` |
| `DemoStress-CpuIo` | `EXEC SalesLT.TableLockAndCpuIoStress @Loops = 100000;` |

Son **seis conexiones de carga**, tres por base de datos. A y B favorecen deadlocks
en la misma base; las dos bases no se bloquean entre sí. Los inicios son asíncronos:
no se garantiza simultaneidad exacta ni deadlocks si una conexión falla o llega tarde.
La carga de tabla utiliza otra tabla y no implica por sí sola esperas entre sesiones.

Solo `DemoStress-Coordinator` tendrá una programación: cada **2 horas UTC**, sin
fecha final. Adquiere un application lock de sesión en la base de jobs, comprueba
si queda **cualquier worker activo en cualquiera de los dos destinos** y, si lo hay,
omite el ciclo completo. No espera para ejecutarlo en cuanto termine el anterior,
no acumula ciclos ni cancela carga por alcanzar las dos horas.

La omisión intencionada queda como **`Failed` con error 51001**, no como el estado
nativo `Skipped` de Elastic Jobs. Así es visible en el historial sin reintentos.
Un coordinador `Succeeded` solo confirma el lanzamiento: comprueba también los
workers y sus ejecuciones por destino. Si el lanzamiento falla a mitad, los workers
ya iniciados continúan y bloquean el ciclo siguiente mientras estén activos.

**Servicio continuo no significa carga continua**: entre ciclos puede haber reposo.
Los workers tienen un timeout de seguridad de **86400 s (24 h)** por destino, no de
dos horas. Tras un fallo/timeout, revisa las sesiones y cualquier rollback pendiente
antes de reanudar; la comprobación de jobs activos no detecta carga manual ni sesiones
huérfanas fuera del agente. No inicies workers manualmente ni les actives horarios.

## 1. Preparar recursos y autenticación

Esta carpeta no despliega infraestructura. Puedes preparar los recursos nuevos
con la [plantilla Bicep y su fichero de parámetros](../../infra/README.md).
Esa plantilla usa ahora acceso publico con firewall, sin endpoints privados;
revisa los permisos de red en los tres servidores antes de instalar los jobs.
Antes de ejecutar la configuración:

1. Crea una **base de jobs dedicada**, distinta de las dos bases de carga. Microsoft
   recomienda S1 o superior como punto de partida. Preferiblemente usa un servidor
   de control separado para no comprometerlo con la carga.
2. Crea un **Elastic Job Agent** asociado a esa base y asígnale una **identidad
   administrada asignada por el usuario (UAMI)**. La identidad de sistema no sirve
   para este escenario. El agente y la base de jobs generan costes.
3. Configura Microsoft Entra y la conectividad del agente a los tres destinos:
   ambas bases de carga **y la base de jobs**, que también será destino del coordinador.
   Si utilizas endpoints privados administrados de Elastic Jobs, apruébalos en cada
   servidor correspondiente. No abras globalmente el firewall como atajo.
4. Asegura capacidad concurrente suficiente para los seis workers y el coordinador,
   y que las bases no estén pausadas/inaccesibles.
5. Instala las [tablas](../CreateTable/Create_All_DemoTables.sql) si faltan y actualiza
   los [procedimientos](../StoredProcedure/Create_All_StoredProcedures.sql) en **ambas**
   bases. Crear las tablas destruye sus datos: nunca lo hagas durante una ejecución.
   La versión actualizada de Ultra limita el payload a 200 caracteres, admite
   `READPAST` bajo `READ_COMMITTED_SNAPSHOT` y solo absorbe el deadlock 1205.
   Los demás errores, incluidos los de CPU/E/S, se propagan al agente.
6. Configura watcher y la investigación de SRE por separado. Registra una línea base.
   Estos jobs no crean alertas, incidentes ni integraciones de SRE.

Usa una identidad/agente dedicados: el permiso de iniciar jobs en la base de control
no queda restringido a los tres workers por nombre.

## 2. Instalar sin activar

### Identidad y conexión de cada script

`REPLACE_JOB_AGENT_IDENTITY` es el **nombre de la UAMI**, no su resource ID,
client ID ni principal/object ID. Usa el valor de `MANAGED_IDENTITY_NAME` en
[`infra/.env`](../../infra/.env) o el output Bicep `jobIdentityName`. Por ejemplo:

```sql
DECLARE @Identity SYSNAME = N'id-datasaturday-jobs';
```

Utiliza el mismo nombre en los dos scripts de instalación. Se utiliza para
`CREATE USER [id-datasaturday-jobs] FROM EXTERNAL PROVIDER`.

| Script | Servidor y base de datos de la conexión | Ejecuciones |
|---|---|---|
| [Grant_TargetPermissions.sql](Grant_TargetPermissions.sql) | `datasaturday01.database.windows.net` → `datasaturdaydb01` | Una vez en esta base |
| [Grant_TargetPermissions.sql](Grant_TargetPermissions.sql) | `datasaturday02.database.windows.net` → `datasaturdaydb02` | Una vez en esta base |
| [Configure_StressJobs.sql](Configure_StressJobs.sql) | Servidor de control → `datasaturdayjobs` (o tu nombre de base de jobs) | Una vez, solo en la base asociada al agente |
| [Monitor_StressJobs.sql](Monitor_StressJobs.sql) | El mismo servidor de control y la misma base de jobs | Cuando quieras consultar el estado |

**No ejecutes estos scripts en `master`.** El script de permisos se ejecuta en
las dos bases de carga; configuración y monitorización se ejecutan en la base
de jobs, no en las bases de carga. Para confirmar tu conexión antes de continuar:

```sql
SELECT CONVERT(NVARCHAR(256), SERVERPROPERTY('ServerName')) AS ServerName,
       DB_NAME() AS DatabaseName;
```

Conéctate a las Bases de datos como administrador autorizado de Microsoft Entra para instalar.
La monitorización solo necesita permisos de lectura de las vistas de jobs,
por ejemplo mediante el rol `jobs_reader` en la base de jobs.

### Orden de instalación

1. Edita `REPLACE_JOB_AGENT_IDENTITY` en
   [Grant_TargetPermissions.sql](Grant_TargetPermissions.sql) y ejecútalo una vez en
   cada base de carga. Concede ejecución de los dos procedimientos y lectura de sus
   tablas para las comprobaciones; no concede `db_owner` ni escritura directa.
2. En [Configure_StressJobs.sql](Configure_StressJobs.sql), sustituye
   `REPLACE_JOB_SERVER`, `REPLACE_JOB_DATABASE` y `REPLACE_JOB_AGENT_IDENTITY`.
   Conéctate a esa base de jobs y ejecútalo. Requiere permisos para administrar jobs,
   crear el usuario y conceder permisos. Crea dos grupos de destinos y cuatro jobs.
   No modifica tablas internas del agente ni crea procedimientos propios en su base.
3. En esa misma base de jobs, ejecuta [Monitor_StressJobs.sql](Monitor_StressJobs.sql).
   Es de **solo lectura**: no inicia carga ni cambia la programación. Debe mostrar cuatro jobs,
   todos con **`enabled = 0`**, dos destinos de carga y uno de control al revisar
   los grupos en el portal.

La configuración rechaza definiciones ya existentes para no sobrescribir horarios
o carga en curso. Ante un error revisa el resultado; no borres objetos para forzar
una reinstalación mientras haya ejecuciones activas.

## 3. Validar y activar más adelante

**Los siguientes bloques sí pueden activar carga. No forman parte de la instalación.**
Antes de una prueba real, reduce temporalmente las iteraciones de los comandos de los
workers mediante `jobs.sp_update_jobstep` o el portal (por ejemplo, 20 para deadlocks
y 10 para CPU/E/S), y restáuralas tras comprobar conectividad, permisos y monitorización.
Usa un cliente SQL con conexión a la **base de jobs**:

```sql
-- Prueba manual de UN ciclo; funciona aunque enabled = 0.
EXEC jobs.sp_start_job @job_name = N'DemoStress-Coordinator';
```

Durante esa prueba, inicia el coordinador otra vez mientras haya workers activos:
debe registrar 51001 y **no crear nuevos workers**. Comprueba los seis destinos
de ejecución, sus horarios y las sesiones desde otra conexión de diagnóstico.
Confirma eventos 1205 reales, no solo mensajes; correlaciona CPU, Data IO, Log IO,
esperas y errores con watcher y SRE. No se garantiza saturación ni E/S física:
Ultra trabaja con cinco filas, hay caché y el producto cruzado se limita a `TOP 1000`.

Después de restaurar los valores agresivos y dejar terminar la prueba, activa
**solo** el coordinador con un anclaje a la siguiente hora en punto UTC.
Este bloque también actualiza el horario de un coordinador ya existente:

```sql
DECLARE @ScheduleEpoch DATETIME2 = '2000-01-01T00:00:00';
DECLARE @FirstRunUtc DATETIME2 = DATEADD(
    HOUR, DATEDIFF(HOUR, @ScheduleEpoch, SYSUTCDATETIME()) + 1, @ScheduleEpoch);
EXEC jobs.sp_update_job
    @job_name = N'DemoStress-Coordinator',
    @enabled = 1,
    @schedule_start_time = @FirstRunUtc,
    @schedule_interval_type = N'Hours',
    @schedule_interval_count = 2;
```

Ese ejemplo programa el primer inicio en la siguiente hora en punto UTC y repite
cada dos horas: si se configura a las 03:53 UTC, los inicios serán 04:00, 06:00,
08:00 UTC, etc. No obliga a que siempre sean horas pares: depende del primer anclaje.
El inicio real puede retrasarse por la planificación del servicio; no es tiempo real.
Editar el fichero de configuración no actualiza jobs existentes: utiliza el bloque
`jobs.sp_update_job` anterior, no reinstales todos los jobs.
Los tres workers siguen con `enabled = 0`: el coordinador los inicia explícitamente.
No hay reintentos automáticos de pasos para evitar repetir parcialmente la carga.

## 4. Observar y detener

[Monitor_StressJobs.sql](Monitor_StressJobs.sql) se ejecuta **en la base de jobs
del servidor de control** (`datasaturdayjobs` si mantuviste el nombre del ejemplo),
no en `master` ni en las bases de carga. Es de solo lectura y consulta programación y últimas
100 filas de historial, con UTC, destino, estado, ID de ejecución y `last_message`.
Comprueba también los workers: el coordinador no espera a su finalización.

Para impedir futuros ciclos:

```sql
EXEC jobs.sp_update_job @job_name = N'DemoStress-Coordinator', @enabled = 0;
```

Deshabilitar **no cancela** ejecuciones. Si el coordinador está activo, cancélalo
en el portal o con `jobs.sp_stop_job` y espera a que deje de estar activo antes de
cancelar los workers, para evitar nuevos lanzamientos durante la parada.
Obtén los IDs de las ejecuciones principales activas:

```sql
SELECT job_name, job_execution_id, lifecycle
FROM jobs.job_executions
WHERE job_name LIKE N'DemoStress-%' AND is_active = 1 AND step_id IS NULL;

-- Sustituye por un ID obtenido arriba; repite para cada ejecución que quieras cancelar.
-- EXEC jobs.sp_stop_job @job_execution_id = 'ID-DE-EJECUCION';
```

Repite la consulta hasta que no haya carga activa y verifica en **ambas bases** que
las sesiones, transacciones y rollbacks han terminado. Solo entonces restablece datos.
Al acabar la sesión, elimina los recursos dedicados que ya no necesites para detener
sus costes; deshabilitar horarios no elimina el agente ni su base.

## Comprobación local sin carga

Desde la raíz del repositorio:

```bash
python3 -m unittest discover -s sql/elastic-jobs -p 'test_*.py'
```

Son comprobaciones estáticas de destinos, programación deshabilitada, comandos,
guardas y consistencia de procedimientos. **No compilan ni ejecutan T-SQL**;
la prueba real de permisos, concurrencia y ausencia de solapamiento sigue pendiente
en Azure y debe hacerse con pocas iteraciones antes de activar la programación.

## Referencias

- [Elastic Jobs: componentes, UAMI, costes y base de jobs como destino](https://learn.microsoft.com/azure/azure-sql/database/elastic-jobs-overview)
- [Crear y administrar jobs con T-SQL](https://learn.microsoft.com/azure/azure-sql/database/elastic-jobs-tsql-create-manage)
- [Programación con sp_add_job](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-add-job-elastic-jobs-transact-sql)
