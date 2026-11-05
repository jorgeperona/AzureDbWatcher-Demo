# Análisis de baseline de Azure SQL watcher

**Nombre de la skill:** `azure-sql-watcher-baseline`

**Descripción:** Compara telemetría de Azure SQL Database watcher en ADX con
una baseline previa y reporta anomalías con evidencias, sin remediar.

## Propósito

Captura o valida una baseline de referencia y analiza un intervalo seleccionado
de Azure SQL Database watcher en busca de desviaciones en:

- Bloqueos prolongados, esperas de bloqueo y timeouts.
- Deadlocks confirmados.
- CPU, E/S de datos y E/S del log.
- Recuento de sesiones y tipos de espera que ayuden a explicar las demás señales.

Usa las herramientas Kusto/ADX conectadas solo para inspección y análisis de
lectura. No generes carga de prueba, ejecutes SQL contra una base de datos
objetivo, termines sesiones ni cambies recursos de Azure.

## Datos necesarios

Antes de consultar, obtén:

1. Identidad del servidor lógico y de la base de datos objetivo.
2. Marcas de inicio y fin UTC de la baseline.
3. Marcas de inicio y fin UTC del análisis, salvo que el usuario solo pida
   capturar la baseline.
4. El escenario del laboratorio asociado al intervalo de análisis, si se conoce.

Si falta algún dato necesario, solicítalo. Nunca elijas intervalos en silencio
ni combines distintos destinos SQL.

## Flujo de trabajo

1. **Valida la fuente.** Confirma el conector Kusto activo, el clúster y la
   base de datos. Descubre las tablas y esquemas disponibles mediante las
   herramientas conectadas de solo lectura. No supongas nombres de tablas o
   columnas de otra instalación del watcher.
2. **Relaciona las señales.** Identifica las marcas de tiempo, dimensiones de
   servidor/base de datos, nombres y unidades de métricas y detalles de eventos
   disponibles. Comprueba si existen realmente gráficos/eventos de deadlock.
   Registra las señales no disponibles; no las sustituyas por métricas ajenas.
3. **Valida la calidad de datos.** Comprueba que ambas ventanas UTC tienen
   suficientes muestras, unidades coherentes y la misma identidad de destino.
   Indica huecos, frecuencia de muestreo y retraso de ingestión. Si las ventanas
   o la carga no son comparables, marca `inconcluso` para esas comparaciones.
4. **Captura la baseline.** Para métricas continuas, resume la distribución de
   referencia con p50 y p95, con agregación y granularidad constantes. Para
   eventos discretos, cuenta los eventos confirmados y las sesiones afectadas.
   Indica el intervalo y la cobertura de muestras.
5. **Analiza el intervalo seleccionado.** Aplica las mismas dimensiones,
   unidades, agregación y granularidad de la baseline. Destaca los valores
   continuos que superen el p95 de referencia e informa la diferencia relativa
   cuando el cálculo sea significativo. Compara los recuentos de eventos
   confirmados con la baseline.
6. **Correlaciona antes de concluir.** Usa identificadores y relaciones de
   sesiones bloqueadas, tipos/duraciones de espera, evidencia de deadlocks y
   cambios cercanos de CPU o E/S cuando estén disponibles. Distingue el síntoma
   observado de una causa respaldada por evidencia.
7. **Informa solo conclusiones respaldadas.** No recomiendes ni ejecutes
   remediaciones salvo que el usuario lo solicite por separado y la política de
   seguridad activa lo permita.

## Reglas de interpretación

- Un timeout de bloqueo no es por sí mismo un deadlock. Confirma los deadlocks
  con eventos/gráficos disponibles o un error 1205 correlacionado.
- Los mensajes de un generador de carga no demuestran que haya ocurrido un
  deadlock.
- El muestreo periódico puede omitir eventos breves. Indica esta limitación.
- Una métrica sobre el p95 de la baseline es una desviación relativa, no
  necesariamente una infracción de nivel de servicio ni una causa raíz.
- Compara solo el mismo servidor/base de datos y periodos con cargas
  comparables. Si difieren el volumen o la configuración, indícalo.
- No infieras que el estado es saludable cuando falte telemetría.
- No describas `sys.event_log` como historial de deadlocks de Azure SQL Database.

## Informe requerido

Devuelve estas secciones:

1. **Resultado:** `anomalía observada`, `sin desviación observada` o
   `inconcluso`.
2. **Alcance:** servidor/base de datos objetivo y ambas ventanas UTC.
3. **Calidad de datos:** base de datos de origen, tablas/campos descubiertos,
   cobertura, unidades, huecos de ingestión y señales no disponibles.
4. **Hallazgos:** señal, p50/p95 de baseline o recuento de eventos, valor o
   recuento analizado, diferencia relativa si es significativa, sesiones
   afectadas, evidencia y confianza (`alta`, `media` o `baja`).
5. **Correlación y límites:** qué respalda la evidencia, qué no demuestra y
   advertencias de muestreo o carga.
6. **Siguiente observación:** una comprobación no destructiva que pueda
   realizar el operador.

No devuelvas un informe vacío que parezca satisfactorio si no se puede leer la
fuente, el esquema o los datos necesarios. Explica el bloqueo y marca el
resultado `inconcluso`.

## Idioma de respuesta

Responde en español. Conserva los nombres de herramientas, tablas y métricas,
los códigos de error y las consultas KQL en su forma original.
