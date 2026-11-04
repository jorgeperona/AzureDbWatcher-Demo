# Pruebas de carga con Azure Load Testing

[English](README.en.md)

Esta carpeta contiene planes Apache JMeter para generar carga contra Azure SQL Database mediante Azure Load Testing. Las pruebas ejecutan consultas de lectura y algunas también insertan filas en `SalesLT.Customer`.

> **Solo para bases de datos de laboratorio.** Las pruebas pueden generar carga intensa, aumentar los costes y dejar filas de prueba en la base de datos. Confirma el servidor y la base de datos antes de cada ejecución. Empieza con una carga reducida y detén la prueba si afecta a otros usuarios.

## Planes disponibles

| Plan | Autenticación | Configuración inicial | Driver JDBC |
|---|---|---|---|
| `copilot-jmeter-sql-authentication.jmx` | Usuario y contraseña SQL, leídos desde secretos de Azure Load Testing | 10 usuarios, rampa de 60 s, duración de 300 s. `num_threads` y `ramp_time` usan propiedades JMeter. | `drivers/mssql-jdbc-12.6.1.jre11.jar` |
| `copilot-jmeter.jmx` | `ActiveDirectoryDefault` del driver JDBC | 300 usuarios, rampa de 5 s, duración de 300 s. Es una carga intensa; redúcela antes de usarla por primera vez. | `drivers/mssql-jdbc-12.6.1.jre11.jar` |
| `jmeter/adventureworks-managed-identity.jmx` | Script Groovy que intenta obtener un token de IMDS | 10 usuarios, rampa de 10 s, duración de 60 s. Plan experimental; no se garantiza que IMDS o este flujo de autenticación estén disponibles en los motores de Azure Load Testing. | `jmeter/mssql-jdbc-12.2.0.jre11.jar` |

Los planes `copilot-jmeter*.jmx` tienen el servidor y la base de datos definidos en sus variables JMeter. Antes de cargarlos, verifica que apuntan al destino de pruebas correcto. El plan `adventureworks-managed-identity.jmx` contiene el destino en su script Groovy y requiere editarlo allí.

## Requisitos

### Destinos del laboratorio

La sesión utiliza dos servidores lógicos de Azure SQL, **`SQLServer01` y `SQLServer02`**, con **una base de datos en cada servidor**, ambas con los datos de ejemplo **AdventureWorksLT**. Configura el plan JMeter con el endpoint real del servidor elegido y el nombre de su base de datos; no asumas que los valores incluidos en el JMX corresponden a ese destino.

**`SalesLT` es un esquema dentro de la base de datos**, no su nombre. AdventureWorksLT incluye las tablas de ejemplo que consultan estos planes, como `SalesLT.Customer` y `SalesLT.Product`. Crear únicamente el esquema `SalesLT` o ejecutar los scripts de tablas de estrés de la carpeta `sql` no instala esas tablas de ejemplo.

### Servicios y acceso

- Una suscripción de Azure y un recurso de Azure Load Testing.
- Una Azure SQL Database de pruebas con el esquema `SalesLT` y las tablas usadas por el plan elegido (por ejemplo, `Customer`, `Product`, `CustomerAddress`, `Address` y `SalesOrderHeader`).
- Conectividad desde los motores de prueba a Azure SQL: configura el acceso de red/firewall o una red virtual para el recurso de Load Testing, según corresponda.
- Para el plan SQL Auth, una cuenta SQL de laboratorio con los permisos mínimos necesarios para leer las tablas consultadas e insertar en `SalesLT.Customer`.
- Para autenticación Microsoft Entra, el principal que realmente presente el token debe existir en la base de datos y tener los permisos necesarios. La identidad administrada del recurso Load Testing permite acceder a secretos de Key Vault cuando se configura; **no** significa por sí sola que el motor JMeter vaya a autenticarse en SQL con esa identidad.

## Configuración en Azure Portal

1. En el recurso Azure Load Testing, crea una prueba mediante **Create** > **Upload a JMeter script**.
2. En **Test plan**, carga el archivo `.jmx` elegido y su JAR JDBC correspondiente. Carga los archivos como archivos adicionales del plan; el driver debe estar disponible en el motor al iniciar JMeter. No dependas de rutas locales a `drivers/` o `jmeter/`.
3. En **Parameters**, para `copilot-jmeter-sql-authentication.jmx`, agrega dos parámetros secretos con referencias a Azure Key Vault:
   - `sql_username`: referencia al secreto que contiene el usuario SQL.
   - `sql_password`: referencia al secreto que contiene la contraseña SQL.
4. Configura la identidad administrada que Azure Load Testing usará para leer esos secretos y concédele acceso de lectura a los secretos en Key Vault. No agregues las credenciales como valores de texto sin formato al JMX ni al repositorio.
5. Revisa el host y la base de datos del JMX, guarda la prueba y ejecútala primero con una carga pequeña. En SQL Auth, `num_threads` y `ramp_time` tienen valores predeterminados de 10 y 60; para reducir la carga inicial, cambia `num_threads` a 1 y considera bajar la duración de 300 a 60 segundos en el JMX antes de cargarlo.
6. Revisa los errores de JMeter y las métricas de Azure SQL durante la ejecución. Confirma que las consultas tienen éxito antes de aumentar usuarios, duración o motores.

`num_threads` y `ramp_time` están expresados como propiedades JMeter (`${__P(...)}`), no como variables de entorno. Para modificarlos, edita los valores de la prueba o configura un archivo de propiedades JMeter en el plan; no asumas que los parámetros de entorno de Azure los reemplazan automáticamente.

## Efectos y precauciones

- Los planes `copilot-jmeter*.jmx` ejecutan `INSERT` en `SalesLT.Customer`; las filas de carga se acumulan y pueden afectar otras pruebas. Usa una base de datos desechable o limpia únicamente filas identificadas como datos de prueba, tras verificarlas.
- `copilot-jmeter.jmx` comienza con 300 usuarios que arrancan en 5 segundos. No uses estos valores para la primera ejecución sin confirmar que la base de datos soporta esa carga.
- La dirección `169.254.169.254` del plan de identidad administrada corresponde a IMDS. No confundas este acceso desde el motor JMeter con la identidad administrada de Azure Load Testing usada para recuperar secretos de Key Vault. Valida el flujo de token y la conexión a SQL antes de usar ese plan.
- La autenticación SQL del plan `copilot-jmeter-sql-authentication.jmx` usa `GetSecret`, una función de Azure Load Testing; el plan necesita la configuración de secretos anterior para ejecutarse allí. Para JMeter local, configura otra forma segura de proporcionar credenciales.

## Documentación de Microsoft

- [Crear y administrar pruebas](https://learn.microsoft.com/azure/app-testing/load-testing/how-to-create-manage-test)
- [Usar secretos y variables de entorno](https://learn.microsoft.com/azure/app-testing/load-testing/how-to-parameterize-load-tests)
- [Usar identidades administradas con Azure Load Testing](https://learn.microsoft.com/azure/app-testing/load-testing/how-to-use-a-managed-identity)
- [Cargar archivos JAR de JMeter](https://learn.microsoft.com/azure/app-testing/load-testing/how-to-use-jmeter-plugins)
