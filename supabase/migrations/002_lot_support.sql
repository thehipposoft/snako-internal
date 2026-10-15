-- Snacko Automations — soporte para "protocolo por lote" (APT 0201)
-- Corre esto en el SQL Editor de Supabase, DESPUÉS de haber corrido schema.sql.
--
-- Qué hace:
--   1. Agrega `lot_reference` a control_event — campo provisorio: hoy las planillas de
--      sal/humedad no traen una columna de lote explícita, así que esto es un stand-in
--      hasta confirmar con Snacko cómo correlacionan lote <-> fecha/línea/producto en la
--      operación real (ver prototipo-protocolo-lote.md).
--   2. Corrige el data_type de dos parámetros de RFP 0243 que quedaron mal por defecto
--      (codigo_equipo y control_visual_color son texto, no numéricos).
--   3. Crea dos vistas: una que "despliega" measurements (jsonb) a filas largas, y otra que
--      calcula N/Promedio/Desvío/Mín/Máx por lote+parámetro — el reemplazo de las fórmulas
--      de Excel del prototipo, ahora como consulta SQL agregada (ver contexto-y-hosting.md).
--   4. Carga datos de ejemplo (SINTÉTICOS) para un lote de prueba, 72 g Cheddar Saladix,
--      mientras conseguimos acceso real a las planillas de Snacko.

-- =====================================================================
-- 1) Lote (provisorio)
-- =====================================================================

alter table control_event add column if not exists lot_reference text;
create index if not exists control_event_lot_idx on control_event (lot_reference);

-- =====================================================================
-- 2) Corrección de data_type
-- =====================================================================

update control_form_parameter
set data_type = 'text'
where key in ('codigo_equipo', 'control_visual_color');

-- =====================================================================
-- 3) Vistas de cálculo
-- =====================================================================

create or replace view control_event_measurement as
select
  ce.id as control_event_id,
  ce.control_form_id,
  ce.lot_reference,
  ce.primary_product_id,
  ce.event_date,
  cfp.key as param_key,
  cfp.label,
  cfp.unit,
  cfp.data_type,
  cfp.sort_order,
  case when cfp.data_type = 'numeric' then (ce.measurements ->> cfp.key)::numeric end as value_numeric,
  case when cfp.data_type = 'text' then ce.measurements ->> cfp.key end as value_text
from control_event ce
join control_form_parameter cfp on cfp.control_form_id = ce.control_form_id
where ce.measurements ? cfp.key;

create or replace view lot_parameter_stats as
select
  cem.lot_reference,
  cem.primary_product_id,
  cem.control_form_id,
  cf.rfp_code,
  cf.name as form_name,
  cem.param_key,
  cem.label,
  cem.unit,
  cem.data_type,
  cem.sort_order,
  count(cem.value_numeric) as n,
  avg(cem.value_numeric) as promedio,
  stddev_samp(cem.value_numeric) as desvio,
  min(cem.value_numeric) as minimo,
  max(cem.value_numeric) as maximo,
  count(*) filter (where cem.data_type = 'text') as n_texto,
  count(*) filter (where cem.data_type = 'text' and cem.value_text = ps.expected_text) as n_conforme,
  ps.lie,
  ps.optimo,
  ps.lse,
  ps.expected_text
from control_event_measurement cem
join control_form cf on cf.id = cem.control_form_id
left join parameter_spec ps
  on ps.param_key = cem.param_key
 and ps.product_id = cem.primary_product_id
where cem.lot_reference is not null
group by cem.lot_reference, cem.primary_product_id, cem.control_form_id, cf.rfp_code, cf.name,
         cem.param_key, cem.label, cem.unit, cem.data_type, cem.sort_order,
         ps.lie, ps.optimo, ps.lse, ps.expected_text;

-- Para el selector de lote en la UI: un lote por fila, con producto y rango de fechas.
create or replace view lot_summary as
select
  ce.lot_reference,
  ce.primary_product_id,
  p.name as product_name,
  min(ce.event_date) as fecha_desde,
  max(ce.event_date) as fecha_hasta,
  count(*) as controles
from control_event ce
left join product p on p.id = ce.primary_product_id
where ce.lot_reference is not null
group by ce.lot_reference, ce.primary_product_id, p.name;

-- =====================================================================
-- 4) Datos de ejemplo SINTÉTICOS — lote 'SN1-1-244', 72 g Cheddar Saladix
-- =====================================================================
-- Mismo enfoque que Protocolo_SN1_1_244_DEMO.xlsx: números inventados pero dentro (y a veces
-- cerca del límite) de las especificaciones reales de parameter_spec, para poder mostrar el
-- cálculo funcionando de punta a punta. Reemplazar por datos reales de Snacko cuando haya acceso.

insert into control_event (
  control_form_id, event_date, event_time, shift_id, line_id,
  primary_product_id, employee_id, measurements, lot_reference, source_row_ref
)
select
  (select id from control_form where rfp_code = 'RFP 0241'),
  date '2026-10-10',
  (time '06:00' + (gs * interval '25 minutes')),
  (((gs - 1) % 3) + 1)::smallint,
  1,
  (select id from product where name = '72 g Cheddar Saladix'),
  (select id from employee order by random() limit 1),
  jsonb_build_object(
    'sal_pct', round((1.15 + random() * 0.35)::numeric, 2),
    'sal_pct_2', round((1.15 + random() * 0.35)::numeric, 2)
  ),
  'SN1-1-244',
  'seed sintético — prototipo MVP'
from generate_series(1, 15) as gs;

insert into control_event (
  control_form_id, event_date, event_time, shift_id, line_id,
  primary_product_id, employee_id, measurements, lot_reference, source_row_ref
)
select
  (select id from control_form where rfp_code = 'RFP 0243'),
  date '2026-10-10',
  (time '06:00' + (gs * interval '25 minutes')),
  (((gs - 1) % 3) + 1)::smallint,
  1,
  (select id from product where name = '72 g Cheddar Saladix'),
  (select id from employee order by random() limit 1),
  jsonb_build_object(
    'humedad_pct', round((1.05 + random() * 0.45)::numeric, 2),
    'codigo_equipo', 'EQ-' || (1 + (gs % 2)),
    't_freidor', round((165 + random() * 8)::numeric, 1),
    'velocidad_cinta', round((2.2 + random() * 0.4)::numeric, 2),
    'control_visual_color', 'Conforme',
    'pf_manchadas_pct', round((random() * 4)::numeric, 2),
    'pf_verdes_pct', round((random() * 1.8)::numeric, 2),
    'pf_puntos_oscuros_pct', round((random() * 9)::numeric, 2)
  ),
  'SN1-1-244',
  'seed sintético — prototipo MVP'
from generate_series(1, 15) as gs;

-- Marca compliant por fila, comparando cada lectura contra su especificación.
update control_event ce
set compliant = (ce.measurements ->> 'sal_pct')::numeric between ps.lie and ps.lse
from parameter_spec ps
where ce.lot_reference = 'SN1-1-244'
  and ce.control_form_id = (select id from control_form where rfp_code = 'RFP 0241')
  and ps.param_key = 'sal_pct'
  and ps.product_id = ce.primary_product_id;

update control_event ce
set compliant = (ce.measurements ->> 'humedad_pct')::numeric between ps.lie and ps.lse
from parameter_spec ps
where ce.lot_reference = 'SN1-1-244'
  and ce.control_form_id = (select id from control_form where rfp_code = 'RFP 0243')
  and ps.param_key = 'humedad_pct'
  and ps.product_id = ce.primary_product_id;
