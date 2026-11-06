"""Offline contract checks only; these do not execute or compile T-SQL."""

import re
import unittest
from datetime import datetime, timedelta
from pathlib import Path


HERE = Path(__file__).resolve().parent
SQL = HERE.parent
CONFIG = (HERE / "Configure_StressJobs.sql").read_text()
TOKEN = re.compile(r"--[^\n]*|/\*.*?\*/|N?'(?:''|[^'])*'", re.DOTALL)


def without_comments(text):
    return TOKEN.sub(
        lambda match: "" if match[0].startswith(("--", "/*")) else match[0], text
    )


def normalized(text):
    return re.sub(r"\s+", " ", without_comments(text)).strip()


def command(name):
    match = re.search(
        rf"DECLARE @{name} NVARCHAR\(MAX\) = N'((?:''|[^'])*)';", CONFIG
    )
    if match is None:
        raise AssertionError(f"Missing inline command: {name}")
    return match[1].replace("''", "'")


class PreparedJobsTests(unittest.TestCase):
    def test_installation_cannot_start_load(self):
        executable = TOKEN.sub("", CONFIG)
        self.assertNotRegex(executable, r"(?i)EXEC\s+(?:@\w+\s*=\s*)?jobs\.sp_start_job")
        self.assertNotRegex(executable, r"@enabled\s*=\s*1")
        self.assertEqual(len(re.findall(r"@enabled\s*=\s*0", executable)), 4)
        self.assertIn("@schedule_interval_type = N'Hours'", CONFIG)
        self.assertIn("@schedule_interval_count = 2", CONFIG)
        self.assertNotIn("@schedule_end_time", executable)

    def test_schedule_anchor_is_next_whole_hour(self):
        self.assertIn("@schedule_start_time = @FirstRunUtc", CONFIG)
        formula = "HOUR, DATEDIFF(HOUR, @ScheduleEpoch, SYSUTCDATETIME()) + 1, @ScheduleEpoch"
        self.assertIn(formula, CONFIG)
        for document in ("README.md", "README.en.md"):
            self.assertIn(formula, (HERE / document).read_text())
        epoch = datetime(2000, 1, 1)
        for now in (
            datetime(2026, 11, 6, 3, 53),
            datetime(2026, 11, 6, 4),
            datetime(2026, 12, 31, 23, 59, 59),
        ):
            with self.subTest(now=now):
                elapsed_hours = (now - epoch) // timedelta(hours=1)
                anchor = epoch + timedelta(hours=elapsed_hours + 1)
                self.assertEqual(anchor, now.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1))
                self.assertGreater(anchor, now)
                self.assertEqual((anchor + timedelta(hours=2)).minute, 0)

    def test_exact_load_targets_and_counts(self):
        targets = re.findall(
            r"@server_name = N'([^']+)',\s*@database_name = N'([^']+)'", CONFIG
        )
        self.assertEqual(
            targets,
            [
                ("datasaturday01.database.windows.net", "datasaturdaydb01"),
                ("datasaturday02.database.windows.net", "datasaturdaydb02"),
            ],
        )
        self.assertIn("EXEC SalesLT.GenerateDeadlocksUltra @Loops = 1000;", command("Deadlocks"))
        self.assertIn("EXEC SalesLT.TableLockAndCpuIoStress @Loops = 100;", command("CpuIo"))
        self.assertEqual(CONFIG.count("@command = @Deadlocks"), 2)
        self.assertEqual(CONFIG.count("@command = @CpuIo"), 1)
        self.assertEqual(CONFIG.count("@max_parallelism = 2"), 3)
        self.assertEqual(CONFIG.count("@step_timeout_seconds = 86400"), 3)
        self.assertEqual(CONFIG.count("@retry_attempts = 0"), 4)

    def test_entire_cycle_guard_precedes_every_worker(self):
        coordinator = command("Coordinator")
        self.assertIn("@LockOwner = N'Session'", coordinator)
        self.assertIn("@LockTimeout = 0", coordinator)
        self.assertIn("AND is_active = 1", coordinator)
        guard = coordinator.index("IF EXISTS")
        failure = coordinator.index("THROW 51001", guard)
        starts = list(re.finditer(r"EXEC @StartResult = jobs\.sp_start_job", coordinator))
        self.assertEqual(len(starts), 3)
        self.assertLess(coordinator.index("sys.sp_getapplock"), guard)
        for start in starts:
            self.assertLess(failure, start.start())
        self.assertEqual(coordinator.count("IF @StartResult <> 0 THROW 51002"), 3)
        self.assertEqual(coordinator.count("sys.sp_releaseapplock"), 2)
        self.assertIn("BEGIN CATCH", coordinator)

    def test_individual_and_combined_procedures_match(self):
        combined = (SQL / "StoredProcedure/Create_All_StoredProcedures.sql").read_text()
        for name in ("GenerateDeadlocksUltra", "TableLockAndCpuIoStress"):
            with self.subTest(procedure=name):
                individual = (SQL / f"StoredProcedure/{name}.sql").read_text()
                match = re.search(
                    rf"CREATE OR ALTER PROCEDURE SalesLT\.{name}\b.*?(?=\nGO\b)",
                    combined,
                    re.DOTALL,
                )
                self.assertIsNotNone(match)
                self.assertEqual(normalized(individual), normalized(match[0]))

    def test_ultra_repeated_updates_fit_declared_column(self):
        ultra = (SQL / "StoredProcedure/GenerateDeadlocksUltra.sql").read_text()
        for suffix in ("X", "Y"):
            self.assertIn(f"LEFT(Payload, 199) + '{suffix}'", ultra)
        payload = "A"
        for index in range(100000):
            payload = payload[:199] + ("X" if index % 2 else "Y")
            self.assertLessEqual(len(payload), 200)
        self.assertEqual(len(payload), 200)
        self.assertEqual(ultra.count("ABS(CONVERT(BIGINT, CHECKSUM(NEWID())))"), 3)
        self.assertIn("WITH (READPAST, READCOMMITTEDLOCK)", ultra)
        self.assertIn("IF ERROR_NUMBER() <> 1205\n                THROW;", ultra)
        table_load = (SQL / "StoredProcedure/TableLockAndCpuIoStress.sql").read_text()
        self.assertRegex(table_load, r"ROLLBACK;\s+THROW;")

    def test_monitoring_is_read_only(self):
        monitor = (HERE / "Monitor_StressJobs.sql").read_text()
        self.assertNotRegex(without_comments(monitor), r"(?i)\b(EXEC|UPDATE|DELETE|INSERT|CREATE|DROP)\b")
        self.assertIn("TOP (100)", monitor)
        self.assertIn("last_message", monitor)

    def test_new_documentation_links_resolve(self):
        for language in ("README.md", "README.en.md"):
            for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", (HERE / language).read_text()):
                if "://" not in target:
                    with self.subTest(document=language, target=target):
                        self.assertTrue((HERE / target.split("#")[0]).exists())


if __name__ == "__main__":
    unittest.main()
