# Tablas de demostración

[English](README.en.md) | [Guía del laboratorio](../README.md)

Estos scripts crean y rellenan las tablas utilizadas por los procedimientos de estrés. El esquema `SalesLT` debe existir previamente.

> Cada script elimina la tabla correspondiente si ya existe. Se pierden sus datos. Detén todas las pruebas antes de crear o restablecer tablas.

## Ficheros y datos iniciales

| Fichero | Tabla en `SalesLT` | Filas | Uso |
|---|---|---:|---|
| [Create_All_DemoTables.sql](Create_All_DemoTables.sql) | Las cuatro tablas siguientes | 5012 en total | Preparación completa |
| [Create_Table_DeadlockStress.sql](Create_Table_DeadlockStress.sql) | `DeadlockStress` | 4, Id 1–4 | Deadlocks con `GenerateDeadlocksAggressive` |
| [Create_Table_DeadlockUltra.sql](Create_Table_DeadlockUltra.sql) | `DeadlockUltra` | 5, Id 1–5 | Deadlocks con `GenerateDeadlocksUltra` |
| [Create_Table_LongBlockTest.sql](Create_Table_LongBlockTest.sql) | `LongBlockTest` | 3, Id 1–3 | Bloqueo prolongado y acceso concurrente |
| [Create_Table_TableLockStress.sql](Create_Table_TableLockStress.sql) | `TableLockStress` | 5000 | Bloqueo de tabla y carga de CPU/E/S |

Las tres primeras tablas tienen `Id INT PRIMARY KEY` y `Payload NVARCHAR(200)`. `DeadlockUltra` añade `UpdatedAt DATETIME`. `TableLockStress` usa un `Id` identity, `Payload NVARCHAR(4000)` y `CreatedAt DATETIME`; se rellena con cadenas de 4000 caracteres mediante una CTE recursiva.

## Ejecución

1. Conecta a la base de datos de laboratorio y confirma el destino con `SELECT DB_NAME();`.
2. Verifica que `SalesLT` existe y que tienes permisos de creación y eliminación de tablas.
3. Ejecuta **el script combinado o los individuales necesarios**, no ambos: el combinado ya contiene las cuatro definiciones.
4. Comprueba los recuentos indicados antes de [crear los procedimientos](../StoredProcedure/README.md).

No hay dependencias entre las cuatro tablas. Si solo necesitas bloqueo prolongado, basta con crear `LongBlockTest` y sus dos procedimientos asociados.

## Restablecimiento

Vuelve a ejecutar el script de la tabla afectada después de detener las cargas y resolver las transacciones abiertas. Recuperarás sus datos iniciales; los procedimientos existentes se conservan.

Los procedimientos de deadlock y bloqueo de fila añaden caracteres a `Payload`. Restablece los datos entre pruebas para evitar errores de truncamiento al alcanzar el límite de 200 caracteres.
