-- Run separately on each stress database as an authorized Microsoft Entra administrator.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Identity SYSNAME = N'REPLACE_JOB_AGENT_IDENTITY';
DECLARE @Server NVARCHAR(256) = CONVERT(NVARCHAR(256), SERVERPROPERTY('ServerName'));

IF NOT ((@Server = N'datasaturday01' AND DB_NAME() = N'datasaturdaydb01')
     OR (@Server = N'datasaturday02' AND DB_NAME() = N'datasaturdaydb02'))
    THROW 51000, 'Connect to one of the two approved laboratory targets.', 1;

IF @Identity LIKE N'REPLACE%'
    THROW 51000, 'Set the user-assigned managed identity attached to the job agent.', 1;

IF OBJECT_ID(N'SalesLT.GenerateDeadlocksUltra', N'P') IS NULL
OR OBJECT_ID(N'SalesLT.TableLockAndCpuIoStress', N'P') IS NULL
    THROW 51000, 'Install the updated stress procedures first.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    IF DATABASE_PRINCIPAL_ID(@Identity) IS NULL
    BEGIN
        DECLARE @CreateUser NVARCHAR(MAX) =
            N'CREATE USER ' + QUOTENAME(@Identity) + N' FROM EXTERNAL PROVIDER;';
        EXEC sys.sp_executesql @CreateUser;
    END;

    DECLARE @Grants NVARCHAR(MAX) =
        N'GRANT EXECUTE ON OBJECT::SalesLT.GenerateDeadlocksUltra TO ' + QUOTENAME(@Identity) + N';
          GRANT EXECUTE ON OBJECT::SalesLT.TableLockAndCpuIoStress TO ' + QUOTENAME(@Identity) + N';
          GRANT SELECT ON OBJECT::SalesLT.DeadlockUltra TO ' + QUOTENAME(@Identity) + N';
          GRANT SELECT ON OBJECT::SalesLT.TableLockStress TO ' + QUOTENAME(@Identity) + N';';
    EXEC sys.sp_executesql @Grants;
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
END CATCH;
