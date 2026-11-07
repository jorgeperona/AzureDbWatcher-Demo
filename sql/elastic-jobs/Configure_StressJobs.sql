-- Run only in the database already initialized by an Elastic Job Agent with a UAMI.
-- This script creates definitions only: all four schedules remain disabled.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @JobServer NVARCHAR(256) = N'sqldemodbwatcherjobs.database.windows.net';
DECLARE @JobDatabase SYSNAME = N'sqldemodbwatcherjobsdb';
DECLARE @Identity SYSNAME = N'umi-sqserverjobs';

IF @JobServer LIKE N'REPLACE%' OR @JobDatabase LIKE N'REPLACE%' OR @Identity LIKE N'REPLACE%'
    THROW 51000, 'Set the job server, job database and assigned managed identity before running.', 1;

IF DB_NAME() <> @JobDatabase
    THROW 51000, 'Connect to the configured job database, not a stress target.', 1;

IF CONVERT(NVARCHAR(256), SERVERPROPERTY('ServerName')) <> REPLACE(@JobServer, N'.database.windows.net', N'')
    THROW 51000, 'The connected server does not match the configured job server.', 1;

IF OBJECT_ID(N'jobs.sp_add_job', N'P') IS NULL
    THROW 51000, 'Create an Elastic Job Agent using this database first.', 1;

IF EXISTS (
    SELECT 1 FROM jobs.jobs
    WHERE job_name IN (N'DemoStress-Coordinator', N'DemoStress-Deadlocks-A',
                       N'DemoStress-Deadlocks-B', N'DemoStress-CpuIo')
)
OR EXISTS (
    SELECT 1 FROM jobs.target_groups
    WHERE target_group_name IN (N'DemoStress-Targets', N'DemoStress-Control')
)
    THROW 51000, 'DemoStress definitions already exist. Review them instead of overwriting them.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    IF DATABASE_PRINCIPAL_ID(@Identity) IS NULL
    BEGIN
        DECLARE @CreateUser NVARCHAR(MAX) =
            N'CREATE USER ' + QUOTENAME(@Identity) + N' FROM EXTERNAL PROVIDER;';
        EXEC sys.sp_executesql @CreateUser;
    END;

    DECLARE @Grants NVARCHAR(MAX) =
        N'GRANT SELECT ON OBJECT::jobs.job_executions TO ' + QUOTENAME(@Identity) + N';
          GRANT EXECUTE ON OBJECT::jobs.sp_start_job TO ' + QUOTENAME(@Identity) + N';';
    EXEC sys.sp_executesql @Grants;

    EXEC jobs.sp_add_target_group @target_group_name = N'DemoStress-Targets';
    EXEC jobs.sp_add_target_group_member
        @target_group_name = N'DemoStress-Targets',
        @target_type = N'SqlDatabase',
        @server_name = N'datasaturday01.database.windows.net',
        @database_name = N'datasaturdaydb01';
    EXEC jobs.sp_add_target_group_member
        @target_group_name = N'DemoStress-Targets',
        @target_type = N'SqlDatabase',
        @server_name = N'datasaturday02.database.windows.net',
        @database_name = N'datasaturdaydb02';

    EXEC jobs.sp_add_target_group @target_group_name = N'DemoStress-Control';
    EXEC jobs.sp_add_target_group_member
        @target_group_name = N'DemoStress-Control',
        @target_type = N'SqlDatabase',
        @server_name = @JobServer,
        @database_name = @JobDatabase;

    DECLARE @Deadlocks NVARCHAR(MAX) = N'
SET NOCOUNT ON;
SELECT SYSUTCDATETIME() AS StartedUtc, DB_NAME() AS DatabaseName, @@SPID AS SessionId;
IF OBJECT_ID(N''SalesLT.GenerateDeadlocksUltra'', N''P'') IS NULL
    THROW 51000, ''Install the stress procedures before starting the jobs.'', 1;
IF (SELECT COUNT(*) FROM SalesLT.DeadlockUltra WHERE Id BETWEEN 1 AND 5) <> 5
    THROW 51000, ''DeadlockUltra requires rows 1 through 5.'', 1;
EXEC SalesLT.GenerateDeadlocksUltra @Loops = 100;';

    DECLARE @CpuIo NVARCHAR(MAX) = N'
SET NOCOUNT ON;
SELECT SYSUTCDATETIME() AS StartedUtc, DB_NAME() AS DatabaseName, @@SPID AS SessionId;
IF OBJECT_ID(N''SalesLT.TableLockAndCpuIoStress'', N''P'') IS NULL
    THROW 51000, ''Install the stress procedures before starting the jobs.'', 1;
IF (SELECT COUNT(*) FROM SalesLT.TableLockStress) <> 5000
    THROW 51000, ''TableLockStress requires the 5000 laboratory rows.'', 1;
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 1000;';

    EXEC jobs.sp_add_job @job_name = N'DemoStress-Deadlocks-A', @enabled = 0;
    EXEC jobs.sp_add_jobstep
        @job_name = N'DemoStress-Deadlocks-A',
        @command = @Deadlocks,
        @target_group_name = N'DemoStress-Targets',
        @retry_attempts = 0,
        @step_timeout_seconds = 86400,
        @max_parallelism = 2;

    EXEC jobs.sp_add_job @job_name = N'DemoStress-Deadlocks-B', @enabled = 0;
    EXEC jobs.sp_add_jobstep
        @job_name = N'DemoStress-Deadlocks-B',
        @command = @Deadlocks,
        @target_group_name = N'DemoStress-Targets',
        @retry_attempts = 0,
        @step_timeout_seconds = 86400,
        @max_parallelism = 2;

    EXEC jobs.sp_add_job @job_name = N'DemoStress-CpuIo', @enabled = 0;
    EXEC jobs.sp_add_jobstep
        @job_name = N'DemoStress-CpuIo',
        @command = @CpuIo,
        @target_group_name = N'DemoStress-Targets',
        @retry_attempts = 0,
        @step_timeout_seconds = 86400,
        @max_parallelism = 2;

    DECLARE @Coordinator NVARCHAR(MAX) = N'
SET NOCOUNT ON;
DECLARE @LockResult INT, @ReleaseResult INT, @StartResult INT;
EXEC @LockResult = sys.sp_getapplock
    @Resource = N''DemoStress-Cycle'',
    @LockMode = N''Exclusive'', @LockOwner = N''Session'', @LockTimeout = 0;
IF @LockResult < 0
    THROW 51001, ''Cycle omitted: another coordinator holds the cycle lock.'', 1;

BEGIN TRY
    IF EXISTS (
        SELECT 1 FROM jobs.job_executions
        WHERE job_name IN (N''DemoStress-Deadlocks-A'', N''DemoStress-Deadlocks-B'', N''DemoStress-CpuIo'')
          AND is_active = 1
    )
        THROW 51001, ''Cycle omitted: workers from the previous cycle are still active.'', 1;

    -- Starts are asynchronous; separate jobs provide separate connections per database.
    EXEC @StartResult = jobs.sp_start_job @job_name = N''DemoStress-Deadlocks-A'';
    IF @StartResult <> 0 THROW 51002, ''Failed to start Deadlocks-A.'', 1;
    EXEC @StartResult = jobs.sp_start_job @job_name = N''DemoStress-Deadlocks-B'';
    IF @StartResult <> 0 THROW 51002, ''Failed to start Deadlocks-B.'', 1;
    EXEC @StartResult = jobs.sp_start_job @job_name = N''DemoStress-CpuIo'';
    IF @StartResult <> 0 THROW 51002, ''Failed to start CpuIo.'', 1;

    EXEC @ReleaseResult = sys.sp_releaseapplock
        @Resource = N''DemoStress-Cycle'', @LockOwner = N''Session'';
    IF @ReleaseResult < 0 THROW 51002, ''Failed to release the cycle lock.'', 1;
END TRY
BEGIN CATCH
    EXEC @ReleaseResult = sys.sp_releaseapplock
        @Resource = N''DemoStress-Cycle'', @LockOwner = N''Session'';
    THROW;
END CATCH;';

    DECLARE @ScheduleEpoch DATETIME2 = '2000-01-01T00:00:00';
    DECLARE @FirstRunUtc DATETIME2 = DATEADD(
        HOUR, DATEDIFF(HOUR, @ScheduleEpoch, SYSUTCDATETIME()) + 1, @ScheduleEpoch);

    EXEC jobs.sp_add_job
        @job_name = N'DemoStress-Coordinator',
        @description = N'Every 2 hours, anchored to a whole UTC hour; omit the cycle if any previous worker is active.',
        @enabled = 0,
        @schedule_start_time = @FirstRunUtc,
        @schedule_interval_type = N'Hours',
        @schedule_interval_count = 2;
    EXEC jobs.sp_add_jobstep
        @job_name = N'DemoStress-Coordinator',
        @command = @Coordinator,
        @target_group_name = N'DemoStress-Control',
        @retry_attempts = 0,
        @step_timeout_seconds = 300,
        @max_parallelism = 1;

    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
END CATCH;

SELECT job_name, enabled, schedule_interval_type, schedule_interval_count, schedule_start_time
FROM jobs.jobs
WHERE job_name LIKE N'DemoStress-%';
