# Azure SQL Database watcher | Demo en directo

### De la carga al diagnóstico: observa lo que ocurre dentro de tu base de datos.

[![Ver la web](https://img.shields.io/badge/VER_LA_WEB-GitHub_Pages-38bdf8?style=for-the-badge)](https://jorgeperona.github.io/AzureDbWatcher-Demo/)
[![Laboratorio SQL](https://img.shields.io/badge/LABORATORIO-T--SQL-6366f1?style=for-the-badge)](sql/README.md)
[![Pruebas de carga](https://img.shields.io/badge/CARGA-JMeter-f59e0b?style=for-the-badge)](loadtesting/README.md)

Material para una sesión práctica sobre **Azure SQL Database watcher**: provoca bloqueos, genera contención y relaciona lo que ejecutas con lo que muestra la monitorización.

> **Solo en laboratorio.** Los scripts modifican datos y pueden provocar bloqueos, consumo de recursos y costes. Los scripts de creación de tablas eliminan los datos de las tablas de demostración existentes. Nunca ejecutes estas pruebas en producción.

## El recorrido de la sesión

```text
PREPARAR              GENERAR CARGA           OBSERVAR              EXPLICAR
Tablas + SPs    -->    SQL / JMeter     -->    Métricas + esperas --> Causa y efecto
```

| Escenario | Qué provocamos | Qué observar |
|---|---|---|
| **Bloqueo prolongado** | Una transacción retiene una fila mientras otra intenta actualizarla | Sesiones bloqueadas, esperas `LCK_M_*` y timeout |
| **Deadlocks** | Varias conexiones actualizan filas en distinto orden | Eventos o gráficos de deadlock; no solo mensajes |
| **Carga de tabla** | Actualizaciones con `TABLOCKX`, cálculos y lecturas | Contención y evolución de CPU y E/S |
| **Carga con JMeter** | Usuarios concurrentes contra Azure SQL | Errores, tiempos de respuesta y métricas de la base de datos |

Los deadlocks no están garantizados en cada ejecución y la carga no garantiza saturación. Correlaciona las sesiones y las horas con la monitorización.

## Empieza por aquí

### Topología del laboratorio

El entorno de la sesión utiliza **dos servidores lógicos de Azure SQL**, `SQLServer01` y `SQLServer02`, con **una base de datos en cada servidor**, ambas con los datos de ejemplo **AdventureWorksLT**.

| Servidor lógico | Base de datos | Datos de ejemplo |
|---|---|---|
| `SQLServer01` | Una base de datos de laboratorio | AdventureWorksLT |
| `SQLServer02` | Una base de datos de laboratorio | AdventureWorksLT |

Las bases de datos de `SQLServer01` y `SQLServer02` se añadirán como destinos a **Azure SQL Database watcher**. El watcher recopilará su telemetría y la almacenará en una base de datos de un **clúster de Azure Data Explorer (ADX)**, del que depende la monitorización de este laboratorio. ADX almacena los datos de monitorización, no las bases de datos AdventureWorksLT.

Prepara primero el clúster ADX y su base de datos de almacenamiento; después configura el watcher con ese almacén, añade ambos destinos SQL y verifica la conectividad y los permisos de recopilación e ingestión antes de generar carga.

**`SalesLT` es un esquema dentro de cada base de datos**, no un servidor ni una base de datos. Por ejemplo, `SalesLT.Customer` identifica la tabla `Customer` del esquema `SalesLT`. AdventureWorksLT ya incluye este esquema y las tablas de ejemplo usadas por JMeter; los scripts SQL del repositorio añaden tablas y procedimientos de estrés al mismo esquema.

Configura cada conexión y plan JMeter con el endpoint real del servidor elegido y el nombre de su base de datos. Para provocar bloqueos o deadlocks entre sesiones, todas las conexiones del escenario deben apuntar a **la misma base de datos del mismo servidor**; las sesiones de `SQLServer01` no bloquean las de `SQLServer02`.

### 1. Prepara el entorno

- Prepara la topología anterior con bases de datos de pruebas aisladas y datos de ejemplo AdventureWorksLT, con permisos para crear tablas y procedimientos.
- Abre SSMS o VS Code con la extensión MSSQL y prepara **varias conexiones independientes**.
- Configura previamente Database watcher y comprueba que puedes consultar su monitorización. Este repositorio **no despliega Azure ni configura el watcher**.
- Para JMeter, sigue sus [requisitos específicos](loadtesting/README.md); las tablas del laboratorio de estrés no sustituyen a las tablas AdventureWorks que consultan esos planes.

### 2. Instala el laboratorio

Confirma la base de datos de destino y crea el esquema `SalesLT` si no existe, siguiendo la [guía del laboratorio](sql/README.md). Después ejecuta, en este orden:

1. [Crear las cuatro tablas de demostración](sql/CreateTable/Create_All_DemoTables.sql).
2. [Crear los cinco procedimientos de estrés](sql/StoredProcedure/Create_All_StoredProcedures.sql).

### 3. Prueba tu primer bloqueo

En la **conexión A**:

```sql
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 30;
```

En la **conexión B**, mientras A mantiene el bloqueo:

```sql
EXEC SalesLT.TryAccessBlockedRow @Id = 1;
```

Observa el timeout de B y las esperas desde una tercera conexión. Cuando termine A, repite B para comparar. **Un timeout no es un deadlock.**

### 4. Observa, detén y restablece

Registra una línea base antes de generar carga. Empieza con pocas iteraciones y un escenario cada vez. Al terminar, comprueba las transacciones abiertas en cada conexión de prueba y sigue la [guía de parada y restablecimiento](sql/README.md#5-detener-y-restablecer).

## Tu mapa del repositorio

| Material | Contenido |
|---|---|
| [Laboratorio SQL](sql/README.md) · [English](sql/README.en.md) | Preparación, escenarios, observación y limpieza |
| [Tablas](sql/CreateTable/README.md) | Datos iniciales y restablecimiento |
| [Procedimientos](sql/StoredProcedure/README.md) | Parámetros, comportamiento y limitaciones |
| [Ejecución y diagnóstico](sql/exec/README.md) | Conexiones concurrentes, consultas y precauciones |
| [Azure Load Testing + JMeter](loadtesting/README.md) · [English](loadtesting/README.en.md) | Planes, autenticación, JDBC y carga gradual |

**Importante para la demo:** el ejecutor global ejecuta los procedimientos en secuencia; no crea concurrencia. Los mensajes de los generadores no bastan para confirmar un deadlock. Revisa las advertencias de las guías antes del evento.

## Web del evento · GitHub Pages

La portada está en [`docs/index.html`](docs/index.html), con estilos propios, diseño adaptable y sin dependencias de compilación. Las guías y los scripts se enlazan al repositorio para que los asistentes puedan replicar la demo.

### Contenido de la presentación

La web integra las **diapositivas 5 a 15** de la presentación de Data Saturday 2026 como contenido HTML accesible, no como imágenes:

- **5–11 · Database watcher:** alcance, arquitectura, destinos SQL, data store, límites, costes, conectividad, identidad y permisos.
- **12–15 · Azure SRE Agent:** gestión de incidentes, ciclo de detección y diagnóstico, mitigación, memoria, capacidades y límites.

Se aclaran las simplificaciones de la presentación sobre el número de destinos por watcher, los costes asociados y la diferencia entre respuesta a incidentes y monitorización APM. La web enlaza la documentación oficial y avisa de la retirada de Database watcher anunciada para el 30 de abril de 2027. El PowerPoint original no se publica como parte del sitio.

### Publicación y personalización

- **Dirección:** https://jorgeperona.github.io/AzureDbWatcher-Demo/
- **Publicación:** [workflow de Pages](.github/workflows/pages.yml), al subir cambios a `main` en la web, este README o el propio workflow; también se puede lanzar desde **Actions → Deploy GitHub Pages → Run workflow**.
- **Configuración:** en **Settings → Pages → Build and deployment**, selecciona **GitHub Actions** como origen.
- **Contenido publicado:** únicamente `docs/`. Las imágenes de la web deben estar en `docs/assets/` y enlazarse desde la portada con rutas relativas como `assets/img_labmap.png`. No se copian SQL, JMX ni drivers al sitio, aunque son accesibles desde el repositorio público.
- **Personalización:** edita la [portada](docs/index.html) y sus [estilos](docs/assets/styles.css). No necesita secretos ni credenciales de Azure.

Para previsualizarla localmente con Python:

```powershell
python -m http.server 8000 --directory docs
```

Abre http://localhost:8000. La publicación inicial requiere que estos archivos estén en `main` y que el workflow termine correctamente.

## Autor de la sesión

**[Jorge Perona Puro](https://sessionize.com/jorgeperona/)** · Microsoft MVP · Microsoft MCT · Azure Cloud Architect en Plain Concepts.

Con 25 años de experiencia en el ecosistema Microsoft, comparte conocimientos sobre Azure e infraestructura cloud con la comunidad hispanohablante. Consulta sus sesiones en [Sessionize](https://sessionize.com/jorgeperona/) y sus artículos en [su blog](https://www.jorgeperona.com/).

## Para seguir explorando

- [Introducción a Database watcher](https://learn.microsoft.com/azure/azure-sql/database-watcher-overview)
- [Documentación de Azure Load Testing](https://learn.microsoft.com/azure/app-testing/load-testing/overview-what-is-azure-load-testing)

**Prepara → provoca → observa → explica.** Y deja el entorno limpio al terminar.
