# Load testing with Azure Load Testing

[Español](README.md)

This folder contains Apache JMeter plans for generating load against Azure SQL Database with Azure Load Testing. The tests run read queries, and some plans also insert rows into `SalesLT.Customer`.

> **Use lab databases only.** Tests can generate significant load, increase costs, and leave test rows in the database. Verify the server and database before each run. Start with a low load and stop the test if it affects other users.

## Available test plans

| Plan | Authentication | Initial settings | JDBC driver |
|---|---|---|---|
| `copilot-jmeter-sql-authentication.jmx` | SQL username and password, read from Azure Load Testing secrets | 10 users, 60-second ramp-up, 300-second duration. `num_threads` and `ramp_time` use JMeter properties. | `drivers/mssql-jdbc-12.6.1.jre11.jar` |
| `copilot-jmeter.jmx` | JDBC driver's `ActiveDirectoryDefault` | 300 users, 5-second ramp-up, 300-second duration. This is a heavy load; reduce it before the first run. | `drivers/mssql-jdbc-12.6.1.jre11.jar` |
| `jmeter/adventureworks-managed-identity.jmx` | Groovy script that attempts to get a token from IMDS | 10 users, 10-second ramp-up, 60-second duration. Experimental; IMDS and this authentication flow are not guaranteed to be available on Azure Load Testing engines. | `jmeter/mssql-jdbc-12.2.0.jre11.jar` |

The `copilot-jmeter*.jmx` plans define the server and database in JMeter variables. Verify that they point to the intended test target before uploading. The `adventureworks-managed-identity.jmx` plan defines its target in the Groovy script and must be edited there.

## Prerequisites

### Lab targets

The session uses two Azure SQL logical servers, **`SQLServer01` and `SQLServer02`**, with **one database on each server**, both populated with the **AdventureWorksLT** sample data. Configure the JMeter plan with the chosen server's actual endpoint and database name; do not assume the values included in the JMX match that target.

**`SalesLT` is a schema inside the database**, not its name. AdventureWorksLT includes the sample tables queried by these plans, such as `SalesLT.Customer` and `SalesLT.Product`. Creating only the `SalesLT` schema or running the stress-table scripts in the `sql` folder does not install these sample tables.

### Services and access

- An Azure subscription and an Azure Load Testing resource.
- A test Azure SQL Database with the `SalesLT` schema and the tables used by the selected plan (for example, `Customer`, `Product`, `CustomerAddress`, `Address`, and `SalesOrderHeader`).
- Network connectivity from the test engines to Azure SQL: configure network/firewall access or a virtual network for the Load Testing resource, as applicable.
- For the SQL Auth plan, a lab SQL account with only the permissions needed to read the queried tables and insert into `SalesLT.Customer`.
- For Microsoft Entra authentication, the principal that actually supplies the token must exist in the database and have the required permissions. The Load Testing resource's managed identity can access Key Vault secrets when configured; **that alone does not mean the JMeter engine will authenticate to SQL as that identity**.

## Configure in the Azure portal

1. In the Azure Load Testing resource, create a test with **Create** > **Upload a JMeter script**.
2. Under **Test plan**, upload the selected `.jmx` file and its matching JDBC JAR. Add the files as test-plan files; the driver must be available on the engine when JMeter starts. Do not rely on local paths such as `drivers/` or `jmeter/`.
3. Under **Parameters**, for `copilot-jmeter-sql-authentication.jmx`, add two secret parameters backed by Azure Key Vault:
   - `sql_username`: reference the secret containing the SQL username.
   - `sql_password`: reference the secret containing the SQL password.
4. Configure the managed identity Azure Load Testing uses to read those secrets and grant it read access to the secrets in Key Vault. Do not put credentials in plain text in the JMX file or repository.
5. Verify the JMX host and database, save the test, and start with a small load. For SQL Auth, `num_threads` and `ramp_time` default to 10 and 60; to reduce the initial load, change `num_threads` to 1 and consider lowering the 300-second duration to 60 seconds in the JMX before uploading.
6. Review JMeter errors and Azure SQL metrics during the run. Confirm that queries succeed before increasing users, duration, or engine instances.

`num_threads` and `ramp_time` are JMeter properties (`${__P(...)}`), not environment variables. To change them, edit the test values or configure a JMeter properties file in the test plan; don't assume Azure environment parameters automatically override them.

## Effects and cautions

- The `copilot-jmeter*.jmx` plans run `INSERT` statements against `SalesLT.Customer`; load-test rows accumulate and can affect other tests. Use a disposable database or clean up only verified test rows.
- `copilot-jmeter.jmx` starts 300 users over 5 seconds. Don't use these settings for the first run without confirming that the database can handle the load.
- The managed identity plan uses `169.254.169.254` for IMDS. Do not confuse IMDS access from the JMeter engine with the Azure Load Testing managed identity used to retrieve Key Vault secrets. Validate token acquisition and the SQL connection before using this plan.
- The SQL Auth plan `copilot-jmeter-sql-authentication.jmx` uses `GetSecret`, an Azure Load Testing function; it needs the secret configuration above to run there. For local JMeter runs, use another secure way to provide credentials.

## Microsoft documentation

- [Create and manage tests](https://learn.microsoft.com/azure/app-testing/load-testing/how-to-create-manage-test)
- [Use secrets and environment variables](https://learn.microsoft.com/azure/app-testing/load-testing/how-to-parameterize-load-tests)
- [Use managed identities with Azure Load Testing](https://learn.microsoft.com/azure/app-testing/load-testing/how-to-use-a-managed-identity)
- [Upload JMeter JAR files](https://learn.microsoft.com/azure/app-testing/load-testing/how-to-use-jmeter-plugins)
