-- Read-only. Run in the Elastic Job Agent database.

-- Query the schedule details for DemoStress jobs
SELECT job_name, enabled, schedule_interval_type, schedule_interval_count,
       schedule_start_time, schedule_end_time
FROM jobs.jobs
WHERE job_name LIKE N'DemoStress-%';

-- Query the active executions for DemoStress jobs
SELECT job_name, target_database_name,
       lifecycle, start_time, last_message
FROM jobs.job_executions
WHERE job_name LIKE N'DemoStress-%'
  AND is_active = 1;

-- Query the recent executions for DemoStress jobs
SELECT TOP (100)
       job_name, job_execution_id, step_id, is_active, lifecycle,
       target_server_name, target_database_name,
       start_time, end_time, last_message
FROM jobs.job_executions
WHERE job_name LIKE N'DemoStress-%'
ORDER BY start_time DESC, job_name, step_id;

