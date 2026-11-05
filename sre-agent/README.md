# Azure SRE Agent: baseline de Azure SQL

Material local para configurar Azure SRE Agent y analizar los escenarios del
laboratorio de Azure SQL Database watcher. No aprovisiona recursos ni modifica
un agente remoto.

Para configurarlo desde la interfaz web preview, sigue el
[paso a paso del portal](step-by-step.md).

## Alcance

El análisis cubre:

- Bloqueos prolongados, esperas de bloqueo y timeouts.
- Deadlocks confirmados, incluidos eventos/gráficos o errores 1205 correlacionados.
- Aumentos relativos de CPU, E/S de datos y E/S del log.
- Sesiones y tipos de espera como contexto para explicar los síntomas.

El agente debe basarse en señales observadas, no en el texto de los generadores
de carga. Un timeout no confirma un deadlock; los deadlocks son probabilísticos.
El agente analiza y reporta: no genera carga, termina sesiones ni cambia la
configuración de Azure.

## Preparación

1. Configura previamente Azure SQL Database watcher y comprueba que los datos
   llegan a su base de datos de Azure Data Explorer (ADX).
2. En Azure SRE Agent, crea un conector Kusto/ADX para el clúster y la base de
   datos del watcher. Configura la identidad y los permisos de solo lectura
   requeridos por el conector en tu entorno.
3. Prueba el conector y confirma que puede enumerar tablas y leer el esquema.
   No asumas nombres de tablas, columnas ni unidades: este repositorio no
   incluye el esquema del almacén.
4. Crea una custom skill llamada `azure-sql-watcher-baseline`. Copia como
   contenido el archivo
   [`skills/azure-sql-baseline.md`](skills/azure-sql-baseline.md)
   o su [versión en inglés](skills/azure-sql-baseline.en.md). Usa como
   descripción: `Compara telemetría de Azure SQL Database watcher en ADX con
   una baseline previa y reporta anomalías con evidencias, sin remediar.`
5. Completa los valores del perfil
   [`baseline-profile.yaml`](baseline-profile.yaml) para documentar el agente,
   el clúster y la base de datos. Es una plantilla local de referencia; no es
   un archivo de despliegue/importación nativo de Azure SRE Agent.

Consulta la [documentación de Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/overview)
y la [guía del laboratorio](../sql/README.md) para el aprovisionamiento y los
permisos de cada entorno.

## Capturar y analizar una baseline

1. Antes de ejecutar una prueba, anota el servidor y la base de datos objetivo,
   y define explícitamente las ventanas UTC de referencia y análisis. Usa una
   ventana representativa sin carga de prueba ni incidentes y comparable en
   horario y nivel de actividad.
2. Ejecuta la skill indicando ambos intervalos y el servidor/base de datos.
   El agente debe revisar el esquema real en ADX, encontrar las tablas y campos
   pertinentes y validar que las marcas de tiempo, dimensiones y unidades
   permiten comparar los dos intervalos.
3. Pide primero la captura de baseline. El resultado debe incluir cobertura,
   calidad y estadísticas de referencia; no debe inferir valores ausentes.
4. Ejecuta un escenario aislado del laboratorio y luego pide el análisis con
   su intervalo UTC. Compara el mismo servidor y base de datos; no mezcles
   destinos, periodos con distinta carga ni métricas con unidades diferentes.
5. Conserva el informe junto al intervalo de la prueba. Si cambian el SKU, la
   configuración de watcher, el patrón de carga o el esquema ADX, captura una
   baseline nueva o explica por qué la anterior sigue siendo comparable.

La comparación es relativa a la distribución observada en la baseline. Para
métricas continuas, informa p50/p95 y valores del intervalo analizado usando la
misma agregación y granularidad; destaca cuando el intervalo actual supera el
p95 de referencia. Para eventos discretos, informa los conteos confirmados en
ambos intervalos. Si la baseline no contiene el evento, no atribuyas severidad
solo por ese hecho: correlaciona duración, sesiones afectadas y señales
relacionadas.

## Ejemplo de solicitud

> Usa la skill `azure-sql-watcher-baseline`. Captura/valida la baseline para
> `<servidor>/<base-de-datos>` entre `<inicio UTC>` y `<fin UTC>`. Analiza la
> prueba entre `<inicio UTC>` y `<fin UTC>`. Identifica bloqueos y timeouts,
> deadlocks confirmados, desviaciones de CPU/E/S y señales de sesiones/esperas.
> Devuelve evidencias y limitaciones; no ejecutes remediaciones.

## Seguridad y límites

- Usa solo la base de datos ADX confirmada para el watcher y consultas de
  lectura. No incluyas credenciales en este directorio.
- No consultes ni alteres tablas SQL de producción desde la skill. El laboratorio
  debe permanecer aislado y sus scripts SQL se ejecutan por separado.
- Si no se puede validar el esquema, la cobertura o la comparabilidad de las
  ventanas, devuelve `inconcluso` con el motivo; no inventes una consulta ni
  declares una anomalía como confirmada.
- No programes tareas recurrentes por defecto. Azure SRE Agent se activa por
  solicitud, alerta o programación configurada; esta plantilla describe un
  análisis bajo demanda.
