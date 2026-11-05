# Paso a paso: Azure SRE Agent en la interfaz preview

[Volver a la guía](README.md)

Esta guía configura el laboratorio desde la interfaz web de Azure SRE Agent:
conexión al ADX de Database watcher, creación de la skill y comparación de
anomalías contra una baseline. No requiere desplegar el perfil YAML.

Los nombres de navegación corresponden a la documentación consultada el
5 de noviembre de 2026. La preview puede cambiar etiquetas o disponibilidad.
Se utiliza el portal [sre.azure.com](https://sre.azure.com), con **Build + setup**
y **Agent Canvas**. Si tu sesión ofrece un selector de experiencia preview,
actívalo antes de seguir; no se presupone que todas las cuentas muestren el
mismo selector.

## 1. Reúne los datos del laboratorio

Ten preparados:

| Dato | Valor que debes localizar |
|---|---|
| Suscripción y grupo de recursos | Donde crearás o tienes el agente |
| Nombre del agente | Por ejemplo, `sre-sql-lab` |
| Clúster ADX | `https://<CLUSTER>.<REGION>.kusto.windows.net` |
| Base de datos ADX | La base de telemetría configurada en Database watcher |
| Destino SQL | Servidor lógico y base de datos que analizarás |
| Ventana de baseline | Inicio y fin UTC sin carga de estrés |
| Ventana de análisis | Inicio y fin UTC del escenario que ejecutarás |

La base de datos ADX **no es** la base AdventureWorksLT. `SalesLT` es un esquema
SQL, no una base de datos ni un destino ADX.

**Comprobación:** Database watcher está recopilando datos recientes de los
destinos. Puedes abrir el almacén ADX y ver su esquema con tu propia identidad.
Eso todavía no demuestra que la identidad del agente tenga acceso.

## 2. Abre o crea el agente

Si ya existe, selecciónalo en [sre.azure.com](https://sre.azure.com) y continúa
en el paso 3.

Para crear uno:

1. Inicia sesión en el tenant del laboratorio.
2. Pulsa **Create agent**.
3. En **Basics**, selecciona **Subscription**, **Resource group**, **Agent name**
   y **Region**.
4. Selecciona un **Model provider** disponible y aprobado para tu entorno.
   Revisa las condiciones de residencia de datos y el coste antes de continuar.
5. En **Application Insights**, selecciona una instancia existente o acepta
   crear una nueva. Esta instrumentación del agente no sustituye al ADX del watcher.
6. Pulsa **Next**, revisa **Review** y pulsa **Create**.
7. Espera al estado **Succeeded** y abre **Set up your agent**.
8. En el asistente de contexto puedes conectar los logs; para seguir una ruta
   única, utiliza la sección **Connectors** descrita en el paso 5. No necesitas
   conectar repositorios ni incidentes para este ejercicio.

Crear el agente requiere **Owner**, o **Contributor** junto con
**User Access Administrator**, sobre el ámbito correspondiente. Activa los
roles PIM necesarios si tu organización los utiliza. La creación genera recursos
e implica costes; revisa el resumen antes de confirmar.

**Comprobación:** puedes abrir el agente y acceder a **Build + setup**.

## 3. Identifica la identidad administrada correcta

1. En el agente, abre **Settings > General**.
2. Localiza **Azure settings** y el enlace a la identidad administrada.
3. Abre en Azure la **user-assigned managed identity (UAMI)** del agente.
4. Copia su **Client ID**.

No confundas el **Client ID** con el **Object/Principal ID**, ni con la identidad
system-assigned usada por la infraestructura del agente. En este ejercicio
seleccionarás la UAMI en el conector.

**Comprobación:** tienes identificada la misma UAMI que elegirás en el paso 5.

## 4. Concede lectura en la base de datos ADX

**Los permisos de datos de ADX no se asignan automáticamente al crear el
conector.** Seleccionar la UAMI solo determina qué identidad se utilizará para
autenticarse; un administrador debe concederle **Database Viewer** por separado.
Si esa identidad ya tiene acceso suficiente, no necesitas repetir la asignación.

Este paso lo realiza un administrador autorizado del almacén, no el agente.
Conéctate al clúster desde el explorador web de ADX y ejecuta, sustituyendo los
marcadores:

```kql
.add database <WATCHER_DATABASE> viewers ('aadapp=<UAMI_CLIENT_ID>')
```

Verifica la asignación:

```kql
.show database <WATCHER_DATABASE> principals
```

El comando `.add` **modifica permisos**. Ejecútalo únicamente sobre la base de
telemetría del laboratorio y con la identidad confirmada.

No concedas permisos de administrador o ingesta al agente para este análisis.
El rol Azure **Reader** en un recurso no sustituye al permiso **Viewer** sobre
los datos de la base ADX.

**Comprobación:** la UAMI aparece como viewer de la base ADX correcta.

## 5. Añade el conector ADX desde la vista preview

La ruta actual de nuevas conexiones usa Azure MCP Kusto; no necesitas buscar
una tarjeta de conector ADX heredado.

1. Abre **Build + setup > Extensions > Connectors**.
2. Pulsa **Add connector**.
3. Selecciona la pestaña **Telemetry**.
4. Selecciona **Azure Data Explorer** y pulsa **Next**.
5. En **Name**, escribe `watcher-adx-lab`.
6. En **Managed identity**, selecciona la UAMI del paso 3 y pulsa **Next**.
7. Pulsa **Create new group**.
8. En **Group name**, escribe `sql-watcher-lab`.
9. Deja **Managed identity** en **(inherit)** para usar la identidad del conector.
10. En **Clusters**, introduce la URL **incluyendo la base de datos**:

    ```text
    https://<CLUSTER>.<REGION>.kusto.windows.net/<WATCHER_DATABASE>
    ```

11. Pulsa **Next** y revisa el nombre, la identidad y el grupo.
12. Habilita la visibilidad para el **meta agent** si usarás el chat principal
    para invocar la skill, como en esta guía.
13. Pulsa **Test connection**.
14. Comprueba que aparece **Connected**. Si aparece **Failed**, abre
    **See details** y corrige el error antes de continuar.
15. Pulsa **Add connector** para guardar.

**Test connection** comprueba el acceso existente; no concede permisos a la UAMI.
Si falla por autorización, revisa la asignación del paso 4.

**Comprobación:** el conector está guardado y su prueba de conexión es correcta.
Si el clúster usa firewall o acceso privado, verifica los
[requisitos de red del servicio](https://learn.microsoft.com/azure/sre-agent/network-requirements);
no abras acceso público indiscriminado para resolver la prueba.

## 6. Comprueba la lectura desde el chat

Abre **New chat** y envía, sustituyendo los valores:

```text
Usa el conector watcher-adx-lab para consultar únicamente la base
<WATCHER_DATABASE> del clúster <ADX_CLUSTER_URL>.
Enumera las tablas disponibles y descubre su esquema.
Identifica los campos de tiempo, servidor y base de datos objetivo.
No ejecutes comandos que modifiquen datos o configuración.
Si no tienes acceso, indica el error concreto.
```

Revisa las llamadas a herramientas y sus resultados. No basta con que el
agente responda que está conectado: debe obtener tablas y campos reales.

**Comprobación:** el agente distingue los destinos SQL del laboratorio dentro
del almacén y no inventa nombres de tablas.

## 7. Crea la skill de baseline

1. Abre **Build + setup > Workflows > Agent Canvas**.
2. En **Create**, selecciona **Skill**.
3. En **Name**, introduce `azure-sql-watcher-baseline`.
4. En **Description**, introduce:

   ```text
   Compara telemetría de Azure SQL Database watcher en ADX con una baseline
   previa y reporta anomalías con evidencias, sin remediar.
   ```

5. En el editor de **SKILL.md**, conserva el bloque YAML inicial que el portal
   sincroniza con los campos del formulario. Debajo del bloque, pega el
   contenido de [`skills/azure-sql-baseline.md`](skills/azure-sql-baseline.md).
6. En **Tools > Choose tools**, selecciona las herramientas del conector que
   permitan descubrir tablas/esquemas y ejecutar consultas KQL de lectura.
   Los nombres concretos dependen del conector: usa los que muestre tu portal,
   no nombres supuestos.
7. No añadas herramientas para ejecutar SQL, generar carga, modificar recursos
   o terminar sesiones.
8. Cierra el selector y pulsa **Create**.

El archivo [`baseline-profile.yaml`](baseline-profile.yaml) es una referencia
local, **no un manifiesto de importación**. Si lo añades en **Files** como
contexto, sustituye primero sus marcadores; subirlo no configura el conector
ni aplica permisos.

**Comprobación:** la skill aparece en Agent Canvas con su nombre, descripción,
instrucciones y herramientas seleccionadas.

## 8. Mantén el análisis en solo lectura

- Para el ADX, mantén únicamente el permiso de datos **Viewer** del paso 4.
- No necesitas añadir acceso general a la suscripción para consultar el ADX
  ya conectado.
- Si añades recursos para contexto, usa
  **Build + setup > Context > Managed resources**, limita el ámbito al
  laboratorio y conserva el nivel **Reader**, no **Privileged**.
- No crees response plans ni tareas programadas para esta primera validación.
  Si los configuras después, selecciona explícitamente **Review** para cada
  plan/tarea; no asumas que heredan un modo seguro.

**Review** regula aprobaciones de operaciones de infraestructura, pero no es
una barrera universal para todas las herramientas externas. El acceso efectivo
de solo lectura depende también de los permisos y de las herramientas habilitadas.

## 9. Captura la baseline antes de la carga

1. Detén o espera a que terminen las cargas del laboratorio, incluidas las
   recurrentes de Elastic Jobs si las activaste.
2. Elige un intervalo UTC terminado con actividad normal comparable y con
   telemetría ya ingerida.
3. Abre **New chat** y envía:

   ```text
   Usa la skill azure-sql-watcher-baseline y el conector watcher-adx-lab.
   Destino: <SERVIDOR_LOGICO>/<BASE_SQL>.
   Fuente: <ADX_CLUSTER_URL>/<WATCHER_DATABASE>.
   Captura solo la baseline del intervalo
   <INICIO_BASELINE_UTC> a <FIN_BASELINE_UTC>.

   Descubre el esquema antes de consultar. Informa cobertura, unidades,
   granularidad, p50/p95 de CPU y E/S disponibles, sesiones/esperas y
   recuentos de eventos confirmados de bloqueo, timeout o deadlock.
   Si una señal no está disponible, indícalo.
   No generes carga ni ejecutes remediaciones.
   ```

4. Sustituye las fechas por timestamps UTC completos, por ejemplo con formato
   `AAAA-MM-DDThh:mm:ssZ`; no envíes los marcadores.
5. Guarda o exporta el informe y las consultas/evidencias obtenidas.

**Comprobación:** la skill se activa y el informe incluye el destino, intervalo,
tablas/campos, cobertura y estadísticas. Si la fuente no permite observar una
señal, debe indicarlo; no debe considerarla saludable por ausencia de datos.

## 10. Ejecuta un escenario y solicita el análisis

1. En tu cliente SQL, no desde el agente, ejecuta un escenario de la
   [guía del laboratorio](../sql/README.md#3-ejecutar-los-escenarios).
2. Registra el inicio y fin UTC, servidor, base SQL, sesiones y parámetros.
3. Espera a que la telemetría del intervalo esté disponible en ADX.
4. En el mismo chat o en uno nuevo, envía:

   ```text
   Usa la skill azure-sql-watcher-baseline y el conector watcher-adx-lab.
   Destino: <SERVIDOR_LOGICO>/<BASE_SQL>.
   Fuente: <ADX_CLUSTER_URL>/<WATCHER_DATABASE>.
   Baseline: <INICIO_BASELINE_UTC> a <FIN_BASELINE_UTC>.
   Análisis: <INICIO_PRUEBA_UTC> a <FIN_PRUEBA_UTC>.
   Escenario ejecutado: <ESCENARIO_Y_PARAMETROS>.

   Compara las ventanas con las mismas unidades y granularidad.
   Busca bloqueos/timeouts, deadlocks confirmados, CPU y E/S elevadas,
   con sesiones y esperas como contexto.
   Devuelve evidencias, diferencias relativas, confianza y limitaciones.
   No confundas timeout con deadlock ni desviación del p95 con causa raíz.
   No ejecutes remediaciones.
   ```

**Comprobación:** cada hallazgo muestra evidencia y comparación con la baseline.
Las señales sin datos o sin ventanas comparables quedan como `inconcluso`.
Un evento breve puede no aparecer en el muestreo; un deadlock no está garantizado
por haber ejecutado el generador.

## 11. Resuelve los fallos más comunes

| Síntoma | Qué revisar |
|---|---|
| No aparecen los menús de esta guía | Confirma el agente seleccionado, tu rol y la experiencia disponible; consulta los enlaces oficiales del final |
| `Test connection` devuelve permisos insuficientes | UAMI seleccionada, Client ID y rol Viewer en la base ADX |
| Clúster inaccesible | URL con región/base de datos y conectividad/firewall admitidos por el servicio |
| El chat no utiliza ADX | Visibilidad del conector para el meta agent y herramientas asignadas a la skill |
| La skill no se activa | Nombre/descripcion, instrucciones guardadas y solicitud explícita de usarla |
| No hay muestras del intervalo | Destino, UTC, estado del watcher y retraso de ingestión |
| Faltan eventos de timeout o deadlock | Comprueba si el esquema recopila esa señal; no la deduzcas de CPU ni de mensajes de los procedimientos |

## Referencias oficiales

- [Crear y configurar el agente](https://learn.microsoft.com/azure/sre-agent/create-and-set-up).
- [Identidad administrada del agente](https://learn.microsoft.com/azure/sre-agent/agent-identity).
- [Conectar ADX mediante Azure MCP Kusto](https://learn.microsoft.com/azure/sre-agent/kusto-connector).
- [Crear una skill en Agent Canvas](https://learn.microsoft.com/azure/sre-agent/create-skill).
- [Administrar permisos](https://learn.microsoft.com/azure/sre-agent/manage-permissions).
- [Modos Review y Autonomous](https://learn.microsoft.com/azure/sre-agent/run-modes).

## Preguntas para la demo

Copia estas solicitudes en el chat de SRE Agent. No son opciones del conector:
el destino SQL y las ventanas se indican en la conversación. Sustituye los
marcadores por tus valores y usa timestamps UTC completos.

Todas las solicitudes se limitan a consultar la telemetría de ADX. No requieren
conectar directamente con SQL ni autorizan cambios en datos o recursos. Si tu
conector no se llama `watcher-adx-lab`, sustituye ese nombre.

### 1. Descubrir las bases de datos monitorizadas

```text
Usa el conector ADX watcher-adx-lab para identificar los servidores lógicos
y las bases de datos SQL monitorizadas por Database watcher.
Descubre primero el esquema y devuelve los destinos encontrados, la primera
y la última muestra disponible para cada uno y las tablas consultadas.
Distingue el historial disponible de los destinos con telemetría reciente.
Consulta solo ADX y no modifiques datos ni configuración.
```

### 2. Comprobar si la telemetría permite hacer la demo

```text
Usa el conector ADX watcher-adx-lab para revisar la cobertura de telemetría
de <SERVIDOR_LOGICO>/<BASE_SQL> entre <INICIO_UTC> y <FIN_UTC>.
Identifica las señales disponibles de CPU, E/S de datos, E/S del log,
sesiones, esperas, bloqueos y deadlocks.
Indica unidades, frecuencia de muestreo, huecos y última muestra.
Si no puedes medir el retraso de ingestión, indícalo.
No interpretes una señal ausente como un estado saludable.
```

### 3. Crear la baseline antes de generar carga

```text
Usa la skill azure-sql-watcher-baseline y el conector watcher-adx-lab.
Captura solo la baseline de <SERVIDOR_LOGICO>/<BASE_SQL> entre
<INICIO_BASELINE_UTC> y <FIN_BASELINE_UTC>, sin carga de estrés conocida.
Devuelve p50/p95 de las métricas continuas disponibles, recuentos de eventos
confirmados y contexto de sesiones/esperas.
Incluye cobertura, unidades, granularidad y consultas utilizadas.
No inventes valores para señales no disponibles ni ejecutes remediaciones.
```

### 4. Explicar qué cambió durante la prueba

```text
Usa la skill azure-sql-watcher-baseline y el conector watcher-adx-lab.
Destino: <SERVIDOR_LOGICO>/<BASE_SQL>.
Baseline: <INICIO_BASELINE_UTC> a <FIN_BASELINE_UTC>.
Prueba: <INICIO_PRUEBA_UTC> a <FIN_PRUEBA_UTC>.
Compara CPU, E/S de datos, E/S del log, sesiones y esperas con las mismas
unidades y granularidad. Resume las principales desviaciones relativas,
su duración observable y la evidencia.
No atribuyas una causa raíz solo por correlación ni ejecutes remediaciones.
```

### 5. Investigar bloqueos y timeouts

```text
Usa el conector ADX watcher-adx-lab para investigar bloqueos en
<SERVIDOR_LOGICO>/<BASE_SQL> entre <INICIO_PRUEBA_UTC> y <FIN_PRUEBA_UTC>.
Si el esquema lo permite, identifica sesiones bloqueadoras y bloqueadas,
relaciones entre ellas, esperas LCK_M_* y duración observada.
Distingue duración de espera registrada de duración inferida por muestreo.
Confirma timeouts solo cuando exista evidencia específica.
No confundas timeout con deadlock ni termines sesiones.
```

### 6. Confirmar si realmente hubo deadlocks

```text
Usa el conector ADX watcher-adx-lab para comprobar si hubo deadlocks en
<SERVIDOR_LOGICO>/<BASE_SQL> entre <INICIO_PRUEBA_UTC> y <FIN_PRUEBA_UTC>.
Busca eventos/gráficos de deadlock o errores 1205 correlacionados, si están
disponibles. Muestra hora UTC, evidencia y sesiones implicadas cuando existan.
No uses los mensajes del generador ni una subida de CPU como prueba.
Si ADX no contiene la señal necesaria, devuelve inconcluso y explica qué falta.
```

### 7. Analizar las esperas predominantes

```text
Usa el conector ADX watcher-adx-lab para analizar las esperas de
<SERVIDOR_LOGICO>/<BASE_SQL> entre <INICIO_PRUEBA_UTC> y <FIN_PRUEBA_UTC>.
Identifica los tipos predominantes y su evolución junto a CPU y E/S.
Comprueba si los valores son acumulativos o por intervalo; usa deltas
válidos si corresponde y señala reinicios o discontinuidades.
Explica qué sugieren las esperas sin presentarlas como causa raíz confirmada.
```

### 8. Buscar consultas asociadas al consumo

```text
Usa el conector ADX watcher-adx-lab para investigar qué consultas se asocian
al consumo de <SERVIDOR_LOGICO>/<BASE_SQL> entre
<INICIO_PRUEBA_UTC> y <FIN_PRUEBA_UTC>.
Comprueba primero si hay telemetría por consulta o por plan.
Si existe, muestra identificadores y métricas disponibles de CPU, duración
y lecturas, explicando su agregación. Evita mostrar literales sensibles.
Si no existe ese detalle, no deduzcas consultas a partir de métricas globales.
```

### 9. Comparar los dos destinos del laboratorio

```text
Usa el conector ADX watcher-adx-lab para comparar
<SERVIDOR_01>/<BASE_SQL_01> y <SERVIDOR_02>/<BASE_SQL_02> entre
<INICIO_UTC> y <FIN_UTC>, manteniendo separados los resultados por destino.
Revisa cobertura, unidades y, si están disponibles, capacidad y carga.
Resume diferencias de CPU, E/S, sesiones y esperas.
No declares que una base rinde peor sin comprobar que la comparación es válida.
```

### 10. Verificar la recuperación y cerrar la demo

```text
Usa la skill azure-sql-watcher-baseline y el conector watcher-adx-lab.
Destino: <SERVIDOR_LOGICO>/<BASE_SQL>.
Baseline: <INICIO_BASELINE_UTC> a <FIN_BASELINE_UTC>.
Periodo posterior a la carga: <INICIO_RECUPERACION_UTC> a <FIN_RECUPERACION_UTC>.
Comprueba si las señales disponibles vuelven a valores comparables con
la baseline y si persisten bloqueos o esperas anómalas observables.
No afirmes que no hay transacciones abiertas si la telemetría no lo demuestra.
Termina con un resumen para la audiencia: qué observamos, qué evidencia
lo respalda, qué no pudimos confirmar y qué comprobaríamos después.
No modifiques datos ni recursos.
```
