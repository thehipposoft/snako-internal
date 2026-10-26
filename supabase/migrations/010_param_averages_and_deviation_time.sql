-- Snacko Automations — promedios por parámetro/línea + hora en el detalle de desviaciones
-- Corre esto DESPUÉS de 009_date_range_filters.sql.
--
-- Feedback de Snacko por mail (2026-10-21):
--  1) En el panel general, al filtrar por período, ver el promedio de cada parámetro medido
--     (Humedad, Defectos, Sal, Rotura, etc.) separado por línea de producción.
--  2) En desviaciones, agregar la hora del control para la trazabilidad (ya la teníamos
--     guardada en control_event.event_time, pero deviation_detail_range no la exponía).
--
-- NOTA: "Sal saborizadas" y "Campos polares", que el cliente pidió ver en el punto 1,
-- todavía NO existen como parámetros en el modelo de datos — no están en ninguna planilla
-- que tengamos cargada todavía (ver "formularios RFP adicionales" en
-- phase1-source-analysis-and-data-model.md, una de las preguntas pendientes para Snacko).
-- Esta función solo puede promediar los parámetros que ya conocemos (Humedad, %PF
-- manchadas/verdes/puntos oscuros, Sal, Sal — lectura 2, Rotura crítica/mayor/rebanada,
-- Peso neto). Cuando se confirmen esos dos parámetros con Snacko, se agregan igual que los
-- demás vía control_form_parameter — no hace falta tocar el frontend ni esta función.

-- =====================================================================
-- 1) Promedios por parámetro y línea
-- =====================================================================

create or replace function quality_parameter_averages(p_date_from date default null, p_date_to date default null)
returns table (
  control_form_id bigint,
  rfp_code text,
  form_name text,
  param_key text,
  label text,
  unit text,
  sort_order integer,
  line_name text,
  avg_value numeric,
  n bigint
)
language sql stable as $$
  select
    cem.control_form_id,
    cf.rfp_code,
    cf.name as form_name,
    cem.param_key,
    cem.label,
    cem.unit,
    cem.sort_order,
    coalesce(cec.line_name, 'Sin asignar') as line_name,
    round(avg(cem.value_numeric), 2) as avg_value,
    count(cem.value_numeric) as n
  from control_event_compliance cec
  join control_event_measurement cem on cem.control_event_id = cec.control_event_id
  join control_form cf on cf.id = cem.control_form_id
  where cem.value_numeric is not null
    and (p_date_from is null or cec.event_date >= p_date_from)
    and (p_date_to is null or cec.event_date <= p_date_to)
  group by cem.control_form_id, cf.rfp_code, cf.name, cem.param_key, cem.label, cem.unit, cem.sort_order, cec.line_name
  order by cem.control_form_id, cem.sort_order, cem.param_key, cec.line_name;
$$;

-- =====================================================================
-- 2) Hora del control en el detalle de desviaciones
-- =====================================================================
-- No se puede hacer con `create or replace function` porque cambia la forma de
-- `returns table` (se agrega event_time) — Postgres no lo permite, hay que borrar y
-- recrear. deviation_by_parameter_range y deviation_by_corrective_action_range, que llaman
-- a esta función, seleccionan columnas puntuales (no `select *`), así que no se rompen.

drop function if exists deviation_detail_range(date, date);

create function deviation_detail_range(p_date_from date default null, p_date_to date default null)
returns table (
  control_event_id bigint,
  event_date date,
  event_time time,
  rfp_code text,
  form_name text,
  param_key text,
  label text,
  unit text,
  value_numeric numeric,
  lie numeric,
  optimo numeric,
  lse numeric,
  line_name text,
  shift_name text,
  employee_name text,
  product_name text,
  corrective_action text,
  remuestreado boolean,
  liberado boolean
)
language sql stable as $$
  select
    ce.id as control_event_id,
    ce.event_date,
    ce.event_time,
    cf.rfp_code,
    cf.name as form_name,
    cem.param_key,
    cem.label,
    cem.unit,
    cem.value_numeric,
    ps.lie,
    ps.optimo,
    ps.lse,
    pl.name as line_name,
    s.name as shift_name,
    e.full_name as employee_name,
    p.name as product_name,
    ce.corrective_action,
    (r.id is not null) as remuestreado,
    r.released as liberado
  from control_event ce
  join control_form cf on cf.id = ce.control_form_id
  join control_event_measurement cem on cem.control_event_id = ce.id
  left join parameter_spec ps
    on ps.param_key = cem.param_key
   and ps.product_id = ce.primary_product_id
  left join production_line pl on pl.id = ce.line_id
  left join shift s on s.id = ce.shift_id
  left join employee e on e.id = ce.employee_id
  left join product p on p.id = ce.primary_product_id
  left join resample r on r.control_event_id = ce.id
  where ce.compliant = false
    and ce.lot_reference is null
    and (p_date_from is null or ce.event_date >= p_date_from)
    and (p_date_to is null or ce.event_date <= p_date_to)
  order by ce.event_date desc, ce.event_time desc, ce.id desc;
$$;
