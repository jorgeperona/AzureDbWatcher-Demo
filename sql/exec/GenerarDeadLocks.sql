-- EJECUTA BLOQUEOS Y DEADLOCKS
-- Genera DeadLocks + Carga CPU + Aumento de LogIO y IO
EXEC SalesLT.GenerateDeadlocksAggressive @Loops = 500;

-- DeadLocks + Carga CPU + Aumento de LogIO y IO - Modo Agresivo
EXEC SalesLT.GenerateDeadlocksUltra @Loops = 1000;

-- Lock Table and CPU
EXEC SalesLT.TableLockAndCpuIoStress @Loops = 100000;

