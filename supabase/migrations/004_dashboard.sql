-- Snacko Automations — datos generales (no atados a un lote) + vistas para el dashboard
-- Corre esto DESPUÉS de 002_lot_support.sql y 003_rotura_peso_envasado.sql.
--
-- A diferencia de 002/003 (que cargan datos de UN lote para la demo del protocolo),
-- esto simula ~75 días de controles de línea normales (sal + humedad, Cheddar 72g,
-- líneas y turnos variados) para poder mostrar tendencias, comparaciones y desviaciones
-- en un dashboard general — no están atados a ningún lote (`lot_reference` null).
--
-- SINTÉTICO, con ~10% de desviaciones a propósito (para que el dashboard tenga algo
-- interesante que mostrar) y remuestreos para una parte de esas desviaciones.

-- =====================================================================
-- 1) Controles de línea — 75 días, sal + humedad, Cheddar 72g
-- =====================================================================

insert into control_event (
  control_form_id, event_date, event_time, shift_id, line_id,
  primary_product_id, employee_id, measurements, source_row_ref
)
select
  (select id from control_form where rfp_code = 'RFP 0241'),
  d::date,
  time '10:00',
  (1 + floor(random() * 3))::smallint,
  (1 + floor(random() * 2))::smallint,
  (select id from product where name = '72 g Cheddar Saladix'),
  (select id from employee order by random() limit 1),
  jsonb_build_object(
    'sal_pct',
    case when random() < 0.1
      then round((case when random() < 0.5 then 0.7 + random() * 0.15 else 1.85 + random() * 0.2 end)::numeric, 2)
      else round((1.1 + random() * 0.5)::numeric, 2)
    end
  ),
  'seed sintético — dashboard general'
from generate_series(current_date - interval '74 days', current_date, interval '1 day') as d;

insert into control_event (
  control_form_id, event_date, event_time, shift_id, line_id,
  primary_product_id, employee_id, measurements, source_row_ref
)
select
  (select id from control_form where rfp_code = 'RFP 0243'),
  d::date,
  time '15:00',
  (1 + floor(random() * 3))::smallint,
  (1 + floor(random() * 2))::smallint,
  (select id from product where name = '72 g Cheddar Saladix'),
  (select id from employee order by random() limit 1),
  jsonb_build_object(
    'humedad_pct',
    case when random() < 0.1
      then round((case when random() < 0.5 then 0.6 + random() * 0.15 else 1.65 + random() * 0.2 end)::numeric, 2)
      else round((1.0 + random() * 0.5)::numeric, 2)
    end
  ),
  'seed sintético — dashboard general'
from generate_series(current_date - interval '74 days', current_date, interval '1 day') as d;

-- Marca compliant comparando cada lectura contra parameter_spec (igual criterio que en 002,
-- pero sin filtrar por lote — cubre todos los controles de sal/humedad de Cheddar 72g).
update control_event ce
set compliant = (ce.measurements ->> 'sal_pct')::numeric between ps.lie and ps.lse
from parameter_spec ps
where ce.control_form_id = (select id from control_form where rfp_code = 'RFP 0241')
  and ps.param_key = 'sal_pct'
  and ps.product_id = ce.primary_product_id
  and ce.measurements ? 'sal_pct';

update control_event ce
set compliant = (ce.measurements ->> 'humedad_pct')::numeric between ps.lie and ps.lse
from parameter_spec ps
where ce.control_form_id = (select id from control_form where rfp_code = 'RFP 0243')
  and ps.param_key = 'humedad_pct'
  and ps.product_id = ce.primary_product_id
  and ce.measurements ? 'humedad_pct';

-- =====================================================================
-- 2) Remuestreos para una parte de las desviaciones recién cargadas
-- =====================================================================

insert into resample (control_event_id, lot_reference, released, resolved_at, notes)
select
  ce.id,
  'N/D (dato general, no atado a protocolo de lote)',
  random() < 0.75,
  (ce.event_date + (1 + floor(random() * 3)) * interval '1 day')::timestamptz,
  'seed sintético — dashboard general'
from control_event ce
where ce.compliant = false
  and ce.source_row_ref = 'seed sintético — dashboard general'
  and random() < 0.7;

-- =====================================================================
-- 3) Vistas para el dashboard
-- =====================================================================

create view control_event_compliance as
select
  ce.id as control_event_id,
  ce.control_form_id,
  cf.rfp_code,
  cf.name as form_name,
  ce.event_date,
  ce.shift_id,
  s.name as shift_name,
  ce.line_id,
  pl.name as line_name,
  ce.primary_product_id,
  p.name as product_name,
  ce.employee_id,
  e.full_name as employee_name,
  ce.compliant
from control_event ce
join control_form cf on cf.id = ce.control_form_id
left join shift s on s.id = ce.shift_id
left join production_line pl on pl.id = ce.line_id
left join product p on p.id = ce.primary_product_id
left join employee e on e.id = ce.employee_id
where ce.compliant is not null;

create view quality_overview as
select
  count(*) as total_controles,
  count(*) filter (where compliant) as conformes,
  count(*) filter (where not compliant) as desviaciones,
  round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
from control_event_compliance;

create view quality_trend_weekly as
select
  date_trunc('week', event_date)::date as semana,
  count(*) as total_controles,
  count(*) filter (where compliant) as conformes,
  round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
from control_event_compliance
group by 1
order by 1;

create view quality_by_line as
select
  coalesce(line_name, 'Sin asignar') as line_name,
  count(*) as total_controles,
  count(*) filter (where compliant) as conformes,
  round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
from control_event_compliance
group by line_name
order by total_controles desc;

create view quality_by_shift as
select
  coalesce(shift_name, 'Sin asignar') as shift_name,
  count(*) as total_controles,
  count(*) filter (where compliant) as conformes,
  round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
from control_event_compliance
group by shift_name
order by total_controles desc;

create view quality_by_employee as
select
  coalesce(employee_name, 'Sin asignar') as employee_name,
  count(*) as total_controles,
  count(*) filter (where compliant) as conformes,
  round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
from control_event_compliance
group by employee_name
order by total_controles desc
limit 10;

create view quality_resample_rate as
select
  (select count(*) from control_event_compliance where not compliant) as total_desviaciones,
  (select count(distinct control_event_id) from resample) as remuestreadas,
  (select count(*) from resample where released) as liberadas,
  round(
    100.0 * (select count(distinct control_event_id) from resample)::numeric
      / nullif((select count(*) from control_event_compliance where not compliant), 0),
    1
  ) as pct_remuestreadas,
  round(
    100.0 * (select count(*) from resample where released)::numeric
      / nullif((select count(*) from resample), 0),
    1
  ) as pct_liberadas;
