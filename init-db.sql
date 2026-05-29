-- ─────────────────────────────────────────────────────────────
-- Script de inicializacion de MySQL.
-- Se ejecuta UNA sola vez, al primer arranque del contenedor
-- (cuando el volumen mysql-data esta vacio).
--
-- Crea las dos bases de datos y otorga permisos al usuario de la
-- aplicacion. El usuario 'appuser' lo crea el entrypoint de MySQL
-- via la variable MYSQL_USER, pero NO le da permisos sobre estas
-- DBs; por eso los GRANT van aqui.
--
-- NOTA: si cambias el secret MYSQL_USER, actualiza el nombre aqui.
-- ─────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS db_ventas
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS db_despachos
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES ON db_ventas.*    TO 'appuser'@'%';
GRANT ALL PRIVILEGES ON db_despachos.* TO 'appuser'@'%';

FLUSH PRIVILEGES;
