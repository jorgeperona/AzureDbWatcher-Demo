SET NOCOUNT ON;

PRINT '--- Inicio: SalesLT.GenerateDeadlocksAggressive ---';
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 100;
PRINT '--- Fin: SalesLT.GenerateDeadlocksAggressive ---';

PRINT '--- Inicio: SalesLT.GenerateDeadlocksUltra ---';
EXEC SalesLT.GenerateDeadlocksUltra @Loops = 500;
PRINT '--- Fin: SalesLT.GenerateDeadlocksUltra ---';

PRINT '--- Inicio: SalesLT.GenerateLongBlock ---';
EXEC SalesLT.GenerateLongBlock @Id = 1, @HoldSeconds = 30;
PRINT '--- Fin: SalesLT.GenerateLongBlock ---';

PRINT '--- Inicio: SalesLT.TryAccessBlockedRow ---';
EXEC SalesLT.TryAccessBlockedRow @Id = 1;
PRINT '--- Fin: SalesLT.TryAccessBlockedRow ---';

PRINT '--- Inicio: SalesLT.TableLockAndCpuIoStress ---';
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 1000;
PRINT '--- Fin: SalesLT.TableLockAndCpuIoStress ---';

PRINT '--- Ejecucion completada ---';