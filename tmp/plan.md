# Guia propuesta: carga recurrente y respuesta con SRE Agent

## Objetivo y alcance

Azure SQL Database de laboratorio con endpoint publico y Database Watcher ya configurado.
Alternar un escenario cada dos horas. Eliminar automaticamente solo bloqueadores
identificados de esta demo tras 60 segundos de bloqueo real. Alertar e informar
sobre deadlocks y CPU/E/S sin mitigarlos.

El usuario ha ampliado el alcance a PLANIFICAR la creacion de los dos componentes
ejecutores y su guia de configuracion. No implementarlos todavia: no modificar
el repositorio, desplegar recursos, ejecutar carga ni habilitar permisos.
Cubrir las dos bases de laboratorio, con escenarios independientes.

## Recomendacion de procedimientos

| Escenario | Procedimiento y punto de partida | Concurrencia y verificacion |
| --- | --- | --- |
| Bloqueo | `SalesLT.GenerateLongBlock`, `@Id = 1`, `@HoldSeconds = 600` como limite de seguridad inicial | Una conexion mantiene el bloqueo; otra intenta actualizar la misma fila y espera. Una tercera observa la cadena. La mitigacion puede comenzar tras 60 s de bloqueo comprobado, no necesariamente completarse entonces. |
| Deadlocks | `SalesLT.GenerateDeadlocksAggressive`, `@Loops = 10` en dos conexiones | Arrancar simultaneamente. Verificar la metrica `deadlock` y el evento/grafo, no los mensajes PRINT. Aumentar sesiones o iteraciones solo tras una prueba controlada. |
| CPU/E/S | `SalesLT.TableLockAndCpuIoStress`, `@Loops = 10` inicialmente | Una conexion; aumentar gradualmente tras medir CPU, Data IO y Log IO. No prometer saturacion ni E/S fisica elevada. |

No usar `GenerateDeadlocksUltra` como primera opcion: anade complejidad, no
garantiza deadlocks y sus tablas diminutas no garantizan E/S elevada.
No usar el ejecutor global: ejecuta en serie y no crea concurrencia.

`TryAccessBlockedRow` espera solamente cinco segundos y captura el error:
una llamada no produce una espera continua de 60 s. Para el escenario automatico,
el runbook necesita una segunda conexion con una instruccion de actualizacion
equivalente y un timeout superior al umbral y al margen de deteccion.
Repetir llamadas de cinco segundos no equivale a una misma espera de 60 s.
La duracion del bloqueador debe cubrir la latencia observada de alerta y agente;
600 s es un limite inicial del laboratorio, no una garantia de respuesta.

## Por que no un trigger SQL

Los triggers T-SQL responden a eventos, no a una hora del reloj. Un trigger DML
ejecutaria la carga dentro de la transaccion que lo dispara, afectando esa operacion.
Un bucle infinito con WAITFOR tampoco sustituye a un planificador fiable.
Azure SQL Database no ofrece SQL Server Agent.

Elastic Jobs permite administrar jobs mediante T-SQL, pero requiere un agente
de trabajos y su base de datos. Para coordinar conexiones concurrentes en esta
demo se ha elegido Azure Automation.

## Configuracion de Azure Automation

1. Crear o reutilizar una cuenta de Automation con identidad administrada.
2. Autorizar esa identidad en la base de laboratorio para ejecutar solamente
   los procedimientos y operaciones de demo necesarios; no usar db_owner como atajo.
3. Comprobar autenticacion Entra, modulos del runtime y conectividad SQL.
   Endpoint publico no significa firewall abierto. Usar salida autorizada;
   si se necesita IP estable, considerar Hybrid Runbook Worker con salida controlada.
   No abrir globalmente el servidor como solucion al firewall.
4. Preparar o reutilizar un runbook PowerShell parametrizado por escenario.
   Debe abrir conexiones independientes, coordinar sus inicios, identificar las
   sesiones de demo y cerrar conexiones incluso si hay errores o cancelaciones.
   Definir timeout total, exclusion de ejecuciones solapadas y captura de errores.
5. Publicarlo y probar cada escenario manualmente antes de enlazar horarios.
6. En Schedules, crear tres recurrencias, todas en UTC y cada seis horas:

| Programacion | Primer inicio de ejemplo | Repeticion | Parametro |
| --- | --- | --- | --- |
| demo-blocking | 00:00 UTC | Cada 6 h | Blocking |
| demo-deadlocks | 02:00 UTC | Cada 6 h | Deadlocks |
| demo-resource-load | 04:00 UTC | Cada 6 h | CpuIo |

Enlazar las tres al mismo runbook, cada una con su parametro. Se obtiene
bloqueo a las 00:00, deadlocks a las 02:00, CPU/E/S a las 04:00 y bloqueo a las 06:00.
Elegir una fecha futura para los primeros inicios y definir una fecha de fin.
La frecuencia no mantiene la carga activa durante dos horas.

## Preparacion para ejecucion repetida

Los Payload de bloqueo y deadlock crecen y pueden superar NVARCHAR(200).
Antes de cada escenario, sin sesiones de demo activas, restablecer solamente
sus datos de laboratorio con una identidad autorizada. No ejecutar el script
global de creacion que elimina tablas como parte rutinaria del horario.

Los generadores de deadlock etiquetan cualquier error capturado como deadlock.
El procedimiento CPU/E/S oculta errores. Automation no puede tratar la finalizacion
del EXEC como prueba de exito: debe contrastarla con eventos, metricas y estado.
Si esto no puede observarse con fiabilidad, documentar la limitacion y no habilitar
la programacion desatendida hasta preparar el ejecutor adecuado.

## Observabilidad y alertas

Mantener dos caminos separados:

- Tiempo real: Azure Monitor -> plan de respuesta SRE Agent -> diagnostico
  -> herramienta restringida de mitigacion, solo para bloqueos de demo.
- Historico: metricas y registros persistidos -> informe SRE Agent cada dos horas.

Watcher almacena telemetria en ADX, pero no concede automaticamente a SRE Agent
acceso a ADX ni capacidad de ejecutar comandos SQL. Configurar y probar por
separado esos accesos. Para SQL, habilitar registros de diagnostico Blocks y
Deadlocks hacia Log Analytics si se usa ese camino. Verificar formato e ingestion
antes de escribir o activar consultas de alerta.

| Senal | Regla inicial | Respuesta |
| --- | --- | --- |
| Bloqueo | Evidencia de espera por bloqueo > 60 s en sesiones de demo | Investigar y revalidar el bloqueador actual antes de proponer/ejecutar cancelacion |
| Deadlocks | `deadlock`, Total > 0 en 5 min, evaluacion cada minuto si esta disponible | Diagnostico e informe, nunca KILL por esta alerta |
| CPU | `cpu_percent`, Average > 70 % en 5 min | Diagnostico e informe |
| E/S de datos o log | `physical_data_read_percent` o `log_write_percent`, Average > 70 % en 5 min | Diagnostico e informe |

Los umbrales de recursos son puntos de partida: calibrarlos con la linea base,
el SKU y la duracion real de carga. No bajar umbrales solamente para fingir saturacion.
`blocked_by_firewall` no mide bloqueo transaccional.

Para bloqueos, elegir la fuente comprobada que exponga la duracion necesaria:
Blocks en Log Analytics o un colector explicito de sesiones/esperas. No asumir
que cualquier registro Blocks contiene exactamente la duracion o que los datos
historicos bastan para decidir un KILL actual. La latencia de muestreo,
ingestion, evaluacion e investigacion impide garantizar una cancelacion al segundo 60.

## SRE Agent: remediacion automatica acotada

1. Conectar Azure Monitor en Incidents > Triggers & response plans.
2. Crear alertas con nombres separados, por ejemplo `LAB-SQL-BLOCK`,
   `LAB-SQL-DEADLOCK` y `LAB-SQL-RESOURCE`, y verificar sus filtros en Incidents preview.
3. Crear un plan de respuesta exclusivo para `LAB-SQL-BLOCK` y un agente
   especializado con solo lectura y una herramienta de cancelacion restringida.
4. Probar primero en Review. Tras validar el circuito y sus controles, activar
   Autonomous solo en ese plan. La peticion del usuario autoriza esa configuracion
   propuesta para el laboratorio, no su activacion desde esta sesion.
5. Los planes de deadlocks/recursos se limitan a lectura y generacion del informe.
   No heredar la herramienta de cancelacion ni permisos de escritura.

### Herramienta necesaria para cancelar

Se ha confirmado que no existe una herramienta SQL utilizable por el agente.
Se creara un runbook de remediacion en una cuenta Automation separada. El agente
lo iniciara mediante sus herramientas Azure/CLI y consultara el resultado del job.
No se alojara una API ni un servidor MCP adicional. No basta con escribir
"ejecuta KILL" en las instrucciones del agente ni con asignar Azure RBAC.

La identidad que ejecuta la cancelacion necesita permisos SQL de observacion y
`KILL DATABASE CONNECTION`, restringidos a la base de laboratorio. Separarla
de la identidad generadora de carga. No exponer ejecucion SQL arbitraria al agente.

La operacion debe verificar en el servidor, no solo en el prompt:

- Base de laboratorio permitida y ejecucion de demo registrada y aun activa.
- Identidad de carga dedicada, etiqueta de aplicacion y marcador de ejecucion.
  Una etiqueta por si sola no es una frontera de seguridad.
- Bloqueador raiz de una espera real superior a 60 s, no una sesion bloqueada.
- Sesion y momento de conexion coherentes con la ejecucion registrada.
- Revalidacion inmediatamente antes de cancelar para reducir el riesgo de
  reutilizacion de SPID; rechazar datos antiguos o identidad ambigua.
- Exclusiones: conexiones del watcher, del agente, de administracion y de
  cualquier otra carga, aunque esten en la misma base.
- Una cancelacion por sesion/ejecucion, registro de evidencia y estado posterior.

El permiso KILL DATABASE CONNECTION es amplio dentro de la base: el control
de alcance debe implementarse en la herramienta autorizada. Un prompt no garantiza
que solo se cancelen sesiones de demo. Si no existe esa herramienta con controles,
mantener Review y considerar la mitigacion automatica pendiente, no configurada.

KILL inicia rollback; los bloqueos pueden persistir mientras termina. Consultar
estado y verificar la desaparicion de la cadena. No repetir KILL ciegamente.
Si la sesion ya termino, registrarlo como sin accion necesaria, no como mitigacion.
Los deadlocks los resuelve el motor eligiendo una victima; el agente analiza
el incidente historico y no intenta cancelar una sesion que puede haber desaparecido.

## Informe cada dos horas

En SRE Agent > Automation > Create > Scheduled task:

- Seleccionar un agente de solo lectura y un destino de notificacion disponible.
- Configurar Custom cron UTC: `15 */2 * * *`.
- Consultar las dos ultimas horas completas y un margen de solapamiento para
  ingestion; deduplicar eventos ya incluidos. Indicar la ventana exacta UTC.
- Consultar metricas, eventos de deadlock y bloqueos, datos Watcher accesibles,
  ejecuciones de Automation y acciones de remediacion.
- Incluir escenario esperado y realmente ejecutado, evidencia, sesiones,
  maxima duracion de bloqueo, numero de deadlocks, CPU/E/S, accion y resultado.
- Distinguir entre "sin evidencia", "fuente inaccesible", "evento resuelto"
  y "sin incidentes". No inventar causalidad o exito.

El desfase de 15 minutos es inicial, no una garantia de ingestion. La primera
validacion debe comprobar que el informe realmente ve los eventos finalizados.
Un informe periodico no sustituye al disparo rapido por alerta para liberar bloqueos.

## Todos de configuracion y comprobacion

1. Confirmar la disponibilidad de runbook concurrente y herramienta SQL restringida.
2. Verificar identidades, conectividad y fuentes historicas de datos.
3. Configurar escenarios y tres programaciones de Automation.
4. Configurar alertas y planes separados de SRE Agent.
5. Configurar el informe periodico.
6. Validar de extremo a extremo y solamente entonces habilitar la recurrencia.

## Criterios de validacion

- Bloqueo: observar espera continua > 60 s; confirmar alerta, eleccion del
  bloqueador raiz, cancelacion automatica registrada y finalizacion del rollback.
- Controles negativos: una sesion ajena a la demo y una espera < 60 s no se cancelan.
  Una alerta antigua no autoriza cancelar un nuevo ocupante del mismo SPID.
- Deadlock: evento o metrica real y diagnostico sin remediacion.
- CPU/E/S: metricas por encima del umbral calibrado y alerta sin remediacion;
  una llamada que acaba sin carga observable no cuenta como prueba superada.
- Informe: encuentra eventos ya finalizados y correlaciona cada escenario sin
  confundir PRINT o timeouts con deadlocks.
- Recurrencia: historial de los tres escenarios, un inicio cada dos horas,
  sin solapamientos, crecimiento ilimitado de datos ni transacciones abandonadas.
- Parada: deshabilitar horarios y automatismos; cancelar solo sesiones
  identificadas de demo y comprobar transacciones/rollback.

## Documentacion oficial consultada

- [Programaciones de Automation](https://learn.microsoft.com/azure/automation/shared-resources/schedules)
- [Respuesta a incidentes en SRE Agent](https://learn.microsoft.com/azure/sre-agent/automate-incidents)
- [Tareas programadas de SRE Agent](https://learn.microsoft.com/azure/sre-agent/scheduled-tasks)
- [Flujos y cron UTC](https://learn.microsoft.com/azure/sre-agent/automate-workflows)
- [Conectores SRE Agent](https://learn.microsoft.com/azure/sre-agent/connectors)
- [Metricas SQL Database](https://learn.microsoft.com/azure/azure-monitor/reference/supported-metrics/microsoft-sql-servers-databases-metrics)
- [Exportacion de diagnosticos SQL](https://learn.microsoft.com/azure/azure-sql/database/metrics-diagnostic-telemetry-logging-streaming-export-configure?view=azuresql)
- [KILL y permisos](https://learn.microsoft.com/sql/t-sql/language-elements/kill-transact-sql?view=azuresqldb-current)

## Disponibilidad confirmada y arquitectura elegida

El usuario confirma que no dispone ni del runbook de carga ni de una herramienta
SQL de cancelacion conectada a SRE Agent.

El usuario solicita ampliar este plan, sin implementacion, para crear:

1. Un runbook de carga concurrente en una cuenta Automation de carga.
2. Un runbook de remediacion en OTRA cuenta Automation, sin API/MCP adicional.

Ambos aceptaran solamente un identificador de destino de una lista configurada
de dos bases, no endpoints arbitrarios proporcionados por el agente.
Cada escenario actuara dentro de una base; nunca se intentara provocar bloqueos
entre servidores.

## Plan de implementacion futura

### 1. Contratos y configuracion segura

Crear bajo `automation/` dos runbooks, documentacion y pruebas relacionadas:

- `runbooks/Invoke-DemoSqlLoad.ps1`: parametros Target y Scenario.
- `runbooks/Invoke-DemoSqlRemediation.ps1`: Target y RunId; modo de solo
  inspeccion por defecto y opcion explicita de remediacion.
- `README.md` y `README.en.md`: instalacion, identidades, horarios, alertas,
  respuesta, informes, costes, parada y verificaciones.
- `tests/`: pruebas focalizadas de seleccion de sesiones, limites, contratos
  de resultados y errores; usar Pester si esta disponible y documentar requisitos.
- SQL de instalacion en `sql/` para registro de ejecuciones/sesiones y permisos
  de laboratorio, sin recrear las tablas existentes.

Reutilizar los procedimientos existentes. No anadir framework, servicio web
ni una capa MCP. Extraer un helper compartido solo si ambos scripts necesitan
realmente la misma logica; documentar como se importa en Automation.

Usar autenticacion Entra con identidad administrada y conexiones cifradas.
Separar identidad SQL de carga e identidad SQL de remediacion.
Configurar los dos destinos una vez y validar DB_NAME y servidor antes de actuar.
El agente no puede seleccionar texto SQL, SPID, comando de shell o servidor
arbitrarios para la operacion de remediacion.

### 2. Runbook de carga concurrente y repetible

- Implementar los tres escenarios con conexiones independientes y tiempos
  maximos de conexion, comando y ejecucion total.
- Registrar RunId, Target, escenario, inicio UTC, vencimiento, identidad,
  sesion y hora de conexion. La identidad de remediacion podra leer ese registro;
  otras cargas no podran registrar sus sesiones como demo.
- Serializar escenarios por base con un bloqueo de aplicacion o mecanismo SQL
  equivalente. Permitir concurrencia entre las dos bases.
- Restablecer solo los datos del escenario, cuando no haya ejecucion activa.
  No ejecutar DROP TABLE ni recrear los objetos como limpieza periodica.
- Bloqueo: abrir bloqueador y una espera continua independiente. Registrar y
  comprobar que el segundo participante esta realmente esperando antes de
  considerar iniciado el incidente.
- Deadlocks: lanzar dos conexiones con Aggressive; recoger errores reales y
  comprobar eventos/metricas. No asumir que una ejecucion genera un deadlock.
- CPU/E/S: ejecucion acotada y escalado manual tras medir; no hacer un bucle
  sin limite intentando alcanzar un porcentaje.
- Cerrar y disponer todas las conexiones y transacciones en finally. Tratar
  la desconexion esperada por una mitigacion confirmada de forma distinta a un
  fallo de conexion desconocido; no suprimir errores inesperados.
- Persistir un resumen estructurado con estados Started, Completed, Failed,
  TimedOut o Remediated y sus evidencias; un PRINT no equivale a exito.

Para observabilidad fiable de la demo, la conexion observadora muestreara las
esperas durante el escenario y conservara first-seen, ultima observacion,
sesion, hora de conexion y cadena de bloqueo. No confundir tiempo desde el
inicio del job con duracion continua del bloqueo.

### 3. Ajustes SQL directamente necesarios

Antes de automatizar, endurecer unicamente los procedimientos usados:

- `GenerateLongBlock.sql`: validar fila y duracion; garantizar rollback en
  errores mediante TRY/CATCH y politica de transacciones coherente.
- `GenerateDeadlocksAggressive.sql`: distinguir 1205 de otros errores,
  conservar el comportamiento de continuar ante deadlock esperado y propagar
  errores inesperados.
- `TableLockAndCpuIoStress.sql`: no ocultar errores; rollback y propagacion.
- Actualizar las mismas definiciones en `Create_All_StoredProcedures.sql`.
- Ajustar las guias de procedimientos en ambos idiomas y enlaces desde las
  guias SQL y el README principal.

No modificar Ultra ni otras cargas no utilizadas salvo una necesidad demostrada.
El registro/restablecimiento evita el crecimiento indefinido de Payload sin
alterar innecesariamente la semantica de la demo.

### 4. Runbook de remediacion y permisos del agente

La cuenta de remediacion contendra solamente el runbook autorizado. Su identidad
SQL tendra permisos de diagnostico y cancelacion en las dos bases de laboratorio,
no en otras bases. No usar credenciales administrativas compartidas.

Configurar un rol Azure de minimos privilegios para que la identidad del agente
pueda iniciar y consultar jobs y resultados en ESA cuenta; validar los actions
concretos del proveedor Automation durante la implementacion. No conceder edicion,
publicacion de runbooks, gestion de identidades o asignacion de roles.

El runbook no ejecutara SQL suministrado por el agente. Resolvera el destino
permitido, cargara el registro RunId y evaluara el estado SQL actual.
Comprobara los criterios de seguridad anteriores y la antiguedad real >60 s,
incluyendo bloqueadores raiz sin request activo si fuera necesario.
Solo despues emitira un KILL de un identificador entero validado.

Proporcionar inspeccion sin KILL para las primeras pruebas. Serializar
remediaciones por ejecucion y guardar resultado y evidencia. Reconsultar estado
tras cancelar y distinguir rollback en curso de bloqueo resuelto.
No afirmar que se elimina totalmente la carrera de reutilizacion de SPID:
revalidacion inmediata, sesiones de vida acotada y aislamiento del laboratorio
reducen el riesgo; rechazar cualquier caso ambiguo.

### 5. Alertas y acceso historico

Reutilizar Log Analytics si existe. Habilitar Blocks/Deadlocks y metricas
necesarias, y validar la forma real de sus datos.
Para la alerta de bloqueo, si Blocks no ofrece evidencia suficiente, enviar
las muestras estructuradas del observador a una tabla personalizada mediante
Logs Ingestion API, DCR y permisos minimos de ingestion. La guia debe incluir
estos recursos y su coste, no ocultar que hacen falta.

La regla incluira Target y RunId para que el agente invoque el runbook restringido.
Nunca usar el SPID historico de la alerta como unica autorizacion para KILL.
Las consultas de alerta y de informe se validaran con datos reales antes de
activarlas; no inventar columnas de Watcher o AzureDiagnostics.

Configurar un agente/plan con herramienta Azure para iniciar el runbook de
remediacion y comprobar el job. Sus instrucciones fijaran cuenta, runbook,
destinos y limites. La proteccion efectiva sigue en el runbook y en sus permisos.
El agente de informes y los planes de recursos/deadlocks no dispondran de esa
capacidad de escritura. Verificar los permisos efectivos compartidos de SRE Agent:
la separacion por instrucciones no sustituye al aislamiento de herramientas.

### 6. Dos destinos y horarios

Usar seis enlaces de programacion al runbook de carga: tres por destino.
En cada base, un escenario cada dos horas y cada tipo cada seis horas.

| Base | Bloqueo | Deadlocks | CPU/E/S |
| --- | --- | --- | --- |
| Destino 1 | 00:00 UTC + cada 6 h | 02:00 UTC + cada 6 h | 04:00 UTC + cada 6 h |
| Destino 2 | 01:00 UTC + cada 6 h | 03:00 UTC + cada 6 h | 05:00 UTC + cada 6 h |

El desfase entre bases evita generar carga simultanea por defecto y facilita
atribuir incidentes. La frecuencia de dos horas es POR BASE; globalmente habra
un inicio por hora. La guia explicara este efecto y como alinear horarios si
se desea posteriormente. Un informe cada dos horas cubrira ambos destinos.

### 7. Validacion y entrega

- Comprobar sintaxis PowerShell y T-SQL y ejecutar pruebas focalizadas de
  validacion de entradas, registro, seleccion de bloqueador y errores.
- Pruebas SQL en bases desechables o de laboratorio explicitamente autorizadas.
- Probar bloqueo <60 s, bloqueo >60 s, RunId caducado, destino no permitido,
  SPID reutilizado/identidad distinta, sesion ajena y llamadas duplicadas.
- Comprobar que los planes de deadlocks/CPU no pueden iniciar mitigaciones.
- Verificar restauracion repetida de datos, ejecuciones concurrentes en bases
  distintas y rechazo de solapamiento en la misma base.
- Hacer primero pruebas de inspeccion, despues Review, y activar Autonomous
  solo con la validacion positiva y negativa completada.
- La validacion local no demuestra integracion Azure: registrar por separado
  pruebas unitarias, configuracion pendiente y evidencia end-to-end.
- Entregar scripts, SQL y guias; no desplegar ni encender horarios como parte
  implicita de escribir el codigo.

## Dependencias

Contratos/configuracion -> endurecimiento SQL y runbooks.
Endurecimiento SQL + registro de sesiones -> runbook de carga.
Contrato de registro -> runbook de remediacion.
Runbook de carga + telemetria -> alertas e informe.
Runbook de remediacion + permisos -> plan de respuesta.
Todos los componentes -> validacion integrada -> activacion manual autorizada.

## Estado

Plan ampliado, no implementado. No se han modificado ficheros del repositorio,
creado recursos, asignado permisos ni ejecutado carga.
