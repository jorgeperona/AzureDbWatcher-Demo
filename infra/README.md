# Elastic Jobs con Bicep, sin red privada

[main.bicep](main.bicep) despliega a **ambito de suscripcion**. Crea o actualiza
el grupo de recursos y utiliza [modules/control.bicep](modules/control.bicep)
para crear el servidor SQL, la base S1, la identidad administrada y el agente JA100.
No hay scripts de creacion del servidor, VNet, subredes, endpoints privados ni DNS privado.

El servidor usa **acceso publico, TLS 1.2 y autenticacion solo Entra**. No requiere
contrasenas SQL. Los servidores `datasaturday01` y `datasaturday02` y sus bases
ya deben existir; esta plantilla no los modifica.

## Parametros

Edita el fichero local [.env](.env), excluido de Git. La plantilla versionable
[.env.example](.env.example) contiene solo ejemplos, no datos reales.
[main.bicepparam](main.bicepparam) lee las variables con `readEnvironmentVariable`;
no carga el fichero automaticamente. Todas las variables siguientes son obligatorias:

| Variable | Parametro Bicep / contenido |
|---|---|
| `AZURE_LOCATION` | `location`: region, por ejemplo `swedencentral` |
| `CONTROL_RESOURCE_GROUP` | `controlResourceGroupName`: grupo a crear o actualizar |
| `RESOURCE_TAGS_JSON` | `tags`: objeto JSON, por ejemplo `{"project":"demo"}` |
| `CONTROL_SERVER_NAME` | `controlServerName`: nombre globalmente unico |
| `JOB_DATABASE_NAME` | `jobDatabaseName`: base de jobs |
| `JOB_AGENT_NAME` | `jobAgentName`: nombre del agente |
| `JOB_AGENT_SKU` | `jobAgentSkuName`: `JA100`, `JA200`, `JA400` o `JA800` |
| `JOB_DATABASE_SKU` | `jobDatabaseSkuName`: `S1`, `S2` o `S3` |
| `MANAGED_IDENTITY_NAME` | `managedIdentityName`: nombre de la UAMI |
| `ENTRA_ADMIN_NAME` | `entraAdministratorName`: nombre del administrador existente |
| `ENTRA_ADMIN_OBJECT_ID` | `entraAdministratorObjectId`: object ID, no client ID |
| `ENTRA_ADMIN_TYPE` | `entraAdministratorPrincipalType`: `Group` o `User` |
| `ALLOW_AZURE_SERVICES` | `allowAzureServices`: booleano JSON `true` o `false` |
| `ADMIN_FIREWALL_RULES_JSON` | `administratorFirewallRules`: array JSON de reglas IPv4, o `[]` |
| `STRESS_SUBSCRIPTION_ID` | Suscripcion compartida de los dos servidores de carga existentes |
| `STRESS_RESOURCE_GROUP` | Grupo de recursos compartido de los servidores de carga |
| `STRESS_SERVER_01` | Nombre del primer servidor, por ejemplo `datasaturday01` |
| `STRESS_DATABASE_01` | Primera base de carga, por ejemplo `datasaturdaydb01` |
| `STRESS_SERVER_02` | Nombre del segundo servidor, por ejemplo `datasaturday02` |
| `STRESS_DATABASE_02` | Segunda base de carga, por ejemplo `datasaturdaydb02` |

No hay valores predeterminados ocultos: una variable ausente o JSON invalido hace
fallar la compilacion del fichero de parametros. Usa comillas simples alrededor
del JSON y de textos con espacios, como muestra el ejemplo.

Detalles de los parametros:

- `controlResourceGroupName`: grupo de control que Bicep creara o actualizara.
  Si existe, conserva su ubicacion original; el despliegue tambien aplica sus tags.
- `location`: region del grupo y recursos nuevos, actualmente `swedencentral`.
- `controlServerName`: nombre globalmente unico, distinto de los servidores de carga.
- `entraAdministratorName`, `entraAdministratorObjectId` y
  `entraAdministratorPrincipalType`: usuario o grupo **existente** que sera administrador
  SQL. No crea identidades en Entra. El tenant se obtiene con `subscription().tenantId`;
  no hay parametro `tenantId`.
- Nombres de base, agente e identidad, SKUs y `tags`.
- Bicep construye los IDs de `stressTargets` a partir de las variables `STRESS_*`.
  La suscripcion y el grupo son los de los **destinos de carga**, no seleccionan
  la suscripcion del despliegue. Los dos servidores deben compartir ese ambito.
- `allowAzureServices`: el ejemplo usa `true` para permitir conectividad publica
  de Elastic Jobs al servidor de control mediante la regla SQL `0.0.0.0`.
  **Permite intentos de conexion desde recursos Azure de cualquier suscripcion**,
  no solo desde tu agente; siempre se requieren autenticacion y permisos SQL.
- `administratorFirewallRules`: rangos IPv4 publicos permitidos para administracion.
  Esta vacio inicialmente, por lo que tu portatil no tendra acceso hasta anadir su IP:

```dotenv
ADMIN_FIREWALL_RULES_JSON='[{"name":"Administrator","startIpAddress":"203.0.113.10","endIpAddress":"203.0.113.10"}]'
```

La IP anterior es un ejemplo de documentacion: sustituyela por tu IP publica real.
No uses rangos que abran todo Internet. Sustituye todos los `REPLACE...` y GUID nulos.
Los nombres de destinos deben coincidir con
[Configure_StressJobs.sql](../sql/elastic-jobs/Configure_StressJobs.sql).

## Validar y desplegar

Requisitos previos, realizados por ti:

```bash
az login
az account set --subscription '<ID-SUSCRIPCION-CONTROL>'
```

Necesitas permisos para crear grupos y desplegar recursos a nivel de suscripcion,
incluida la asignacion de la identidad administrada. Desde la raiz del repositorio:

```bash
# Solo en una copia nueva: crea .env sin sobrescribir uno existente.
cp -n infra/.env.example infra/.env
# Edita infra/.env con los valores reales antes de continuar.

# Carga solo un fichero de confianza: source ejecuta codigo de shell.
set -a
source infra/.env
set +a

az bicep build --file infra/main.bicep --stdout > /dev/null
az bicep build-params --file infra/main.bicepparam --stdout > /dev/null

az deployment sub what-if \
  --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam

# Solo tras revisar el what-if y los costes.
az deployment sub create \
  --name datasaturday-elastic-jobs \
  --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

Carga las variables en la misma terminal que ejecuta los comandos; repite la carga
si modificas el fichero o abres otra terminal. `az login` y `az account set` siguen
siendo requisitos previos y no se ejecutan desde el fichero.

Git ignora `.env` y `.env.*`, excepto `.env.example`. No uses `git add -f` para
publicarlos. Los IDs no son contrasenas, pero evita compartir el fichero local.
No guardes credenciales en el ejemplo. Compilar parametros resuelve sus valores:
no publiques el JSON generado, salidas de depuracion ni logs con configuracion local.
Esta exclusion no elimina ficheros ya versionados ni sustituye Key Vault para secretos.

No ejecutes `az group create`: el grupo esta incluido en Bicep. No se usa modo
Complete. En un grupo existente, ARM aplica la declaracion, no hace un skip literal.
No reutilices nombres de recursos ajenos. El administrador del servidor se define
durante la creacion; no uses esta plantilla para cambiar administradores de servidores
preexistentes.

## Conectividad y configuracion posterior

1. En los servidores de carga existentes, comprueba **Networking / Public access**.
   Sin los endpoints privados, el agente necesita acceso publico autorizado en
   **ambos servidores**, normalmente mediante **Allow Azure services and resources
   to access this server**. Esa excepcion es amplia, igual que la del servidor
   de control. Esta plantilla no la activa en los destinos existentes.
2. Autoriza tambien tu IP de administracion en esos servidores si es necesario.
   Conectate por el FQDN normal `servidor.database.windows.net`.
3. Instala/actualiza los procedimientos en ambas bases y ejecuta
   [Grant_TargetPermissions.sql](../sql/elastic-jobs/Grant_TargetPermissions.sql)
   con el nombre de la UAMI. Necesitas un administrador Entra en cada destino.
4. Usa los outputs `jobServerFqdn`, `deployedJobDatabaseName` y `jobIdentityName`
   en [Configure_StressJobs.sql](../sql/elastic-jobs/Configure_StressJobs.sql).
5. Sigue la [guia de validacion](../sql/elastic-jobs/README.md).
   Los jobs se crean deshabilitados; desplegar Bicep no genera carga.

**Migracion:** quitar recursos de Bicep no borra los que ya hayas desplegado.
Si existian endpoints privados del agente, revisalos y retiralos expresamente
despues de preparar el acceso publico; mientras existan, el agente puede seguir
usandolos. Revisa tambien VNet, endpoints administrativos y zona DNS privada antiguos.
No se ejecuta ninguna eliminacion automatica. Del mismo modo, cambiar
`allowAzureServices` a `false` no borra una regla previa en despliegues incrementales:
revisa y elimina esa regla explicitamente si quieres revocar la excepcion.

## Costes y validacion local

Se cobran agente, base y cualquier servicio de monitorizacion independiente,
aunque no haya jobs activos. Esta version no crea recursos de red privada.
No crea watcher, ADX, SRE Agent, alertas ni los objetos SQL de los jobs.
No se despliega un servicio de backup ni retencion a largo plazo. Los backups
automaticos de Azure SQL Database son obligatorios y no pueden desactivarse;
se mantiene redundancia local fija para no heredar la opcion geografica por defecto.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s infra -p 'test_*.py'
checkov -d infra/ --framework bicep --skip-download --download-external-modules false --skip-results-upload
```

Las pruebas locales no validan permisos, disponibilidad regional ni conectividad
real. No se ha ejecutado despliegue ni what-if contra Azure.
La compilacion con las variables de ejemplo y las 15 pruebas locales pasan.
Checkov 3.4.3 devuelve dos errores de parsing para Bicep; el intento con ARM
compilado no muestra comprobaciones, por lo que **el escaneo no se considera
validado**, aunque el proceso termine con codigo 0. No se han suprimido politicas.

## Referencias

- [Elastic Jobs y conectividad](https://learn.microsoft.com/azure/azure-sql/database/elastic-jobs-overview)
- [Bicep a ambito de suscripcion](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-subscription)
- [Servidor SQL y administrador Entra](https://learn.microsoft.com/azure/templates/microsoft.sql/2023-08-01/servers)
- [Reglas de firewall SQL y excepcion de Azure](https://learn.microsoft.com/azure/azure-sql/database/firewall-configure)
