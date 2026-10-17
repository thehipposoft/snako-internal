-- Snacko Automations — columna row_hash para que n8n solo reenvíe filas nuevas/modificadas
-- Corre esto DESPUÉS de 007_staging_tables.sql.
--
-- El workflow ahora trae los hashes ya guardados antes de normalizar cada planilla, y
-- compara contra el hash de la fila recién leída — si no cambió, no la vuelve a mandar.
-- Esto evita reenviar las ~6.700 filas del histórico en cada corrida de 30 minutos.

alter table stg_quality_event add column if not exists row_hash text;
alter table sync_issue add column if not exists row_hash text;
