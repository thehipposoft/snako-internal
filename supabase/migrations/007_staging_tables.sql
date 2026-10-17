-- Snacko Automations — tabla de staging + ajuste a sync_issue para el sync vía n8n
-- (Google Sheets → Supabase). Corre esto DESPUÉS de 006_lot_nc_count.sql.
--
-- stg_quality_event es el "aterrizaje" de los datos crudos que n8n lee de las planillas,
-- ANTES de normalizarlos contra las tablas maestras (product/employee/shift/production_line)
-- y convertirlos en filas reales de control_event. Separar esto en dos pasos (aterrizar ->
-- normalizar) permite probar el workflow de n8n ya mismo, sin esperar a tener confirmado
-- el mapeo de nombres de producto/empleado contra los IDs reales.
--
-- sync_issue YA EXISTE (viene de schema.sql) — acá solo le agregamos una restricción unique
-- sobre source_row_ref para poder hacer upsert desde n8n (Prefer: resolution=merge-duplicates
-- necesita una unique/exclusion constraint sobre la columna de conflicto).

create table if not exists stg_quality_event (
  id bigserial primary key,
  source_row_ref text not null unique,       -- "<RFP code>:<fila de la planilla>"
  control_form_rfp_code text not null,       -- "RFP 0241", "RFP 0243", ...
  event_date_raw text,                       -- valor crudo de la celda FECHA
  event_date date,                           -- fecha ya parseada (null si no se pudo)
  event_time text,                           -- valor crudo de HORA (texto, no se intenta parsear todavía)
  shift_raw text,                            -- TURNO normalizado (Mañana/Tarde/Noche) o crudo si no matcheó
  line_raw text,                             -- LINEA normalizada o cruda
  product_primary_raw text,                  -- GRAMAJE (producto 1), texto tal cual la planilla
  product_secondary_raw text,                -- segundo producto, si la línea corría dos a la vez
  employee_raw text,                         -- REALIZO, texto tal cual
  compliant_raw text,                        -- "SI"/"NO"/vacío, tal cual lo tipeó el operador
  observations text,
  corrective_action text,
  resample_raw text,                         -- "N° remuestreo", puede tener más de un lote en un string
  resample_released_raw text,                -- "SI"/"NO"/vacío
  measurements jsonb not null default '{}'::jsonb,   -- lecturas específicas del formulario (sal_pct_1, humedad_pct, etc)
  data_quality_flags text[] not null default '{}',  -- ej. {'unparsed_date','outlier_value'}
  ingested_at timestamptz not null default now(),
  processed_at timestamptz                    -- se completa cuando se normaliza hacia control_event (paso futuro)
);

create index if not exists stg_quality_event_unprocessed_idx
  on stg_quality_event (processed_at)
  where processed_at is null;

-- sync_issue ya existe con columnas (control_form_id, source_row_ref, reason, raw_payload,
-- resolved, created_at) — le agregamos la unique constraint que falta para poder upsertear
-- desde n8n por source_row_ref. control_form_id se deja en null desde n8n (evita tener que
-- resolver el FK ahí mismo); el rfp_code igual queda guardado dentro de raw_payload.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'sync_issue_source_row_ref_key'
  ) then
    alter table sync_issue add constraint sync_issue_source_row_ref_key unique (source_row_ref);
  end if;
end $$;
