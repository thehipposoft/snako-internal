-- Snacko Automations — funciones con rango de fechas para el dashboard y desviaciones
-- Corre esto DESPUÉS de 008_row_hash.sql.
--
-- Hasta ahora quality_overview / quality_trend_weekly / quality_by_line / quality_by_shift /
-- quality_by_employee / quality_resample_rate / deviation_by_parameter / deviation_by_corrective_action
-- eran vistas fijas (siempre sobre TODO el histórico). Esto agrega una versión en función para
-- cada una, con dos parámetros opcionales (p_date_from, p_date_to) — NULL en cualquiera de los
-- dos significa "sin límite de ese lado", así que llamarlas sin argumentos da exactamente el
-- mismo resultado que las vistas originales (que NO se tocan ni se borran, por si algo más las usa).
--
-- El frontend (src/app/page.tsx, src/app/desviaciones/page.tsx) pasa a usar estas funciones vía
-- supabase.rpc(...) en vez de supabase.from(vista).select("*"), para poder filtrar por el rango
-- de fechas que elige el usuario en el selector del dashboard.

-- =====================================================================
-- Portada (quality_*)
-- =====================================================================

create or replace function quality_overview(p_date_from date default null, p_date_to date default null)
returns table (
  total_controles bigint,
  conformes bigint,
  desviaciones bigint,
  pct_cumplimiento numeric
)
language sql stable as $$
  select
    count(*) as total_controles,
    count(*) filter (where compliant) as conformes,
    count(*) filter (where not compliant) as desviaciones,
    round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
  from control_event_compliance
  where (p_date_from is null or event_date >= p_date_from)
    and (p_date_to is null or event_date <= p_date_to);
$$;

create or replace function quality_trend_weekly(p_date_from date default null, p_date_to date default null)
returns table (
  semana date,
  total_controles bigint,
  conformes bigint,
  pct_cumplimiento numeric
)
language sql stable as $$
  select
    date_trunc('week', event_date)::date as semana,
    count(*) as total_controles,
    count(*) filter (where compliant) as conformes,
    round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
  from control_event_compliance
  where (p_date_from is null or event_date >= p_date_from)
    and (p_date_to is null or event_date <= p_date_to)
  group by 1
  order by 1;
$$;

create or replace function quality_by_line(p_date_from date default null, p_date_to date default null)
returns table (
  line_name text,
  total_controles bigint,
  conformes bigint,
  pct_cumplimiento numeric
)
language sql stable as $$
  select
    coalesce(line_name, 'Sin asignar') as line_name,
    count(*) as total_controles,
    count(*) filter (where compliant) as conformes,
    round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
  from control_event_compliance
  where (p_date_from is null or event_date >= p_date_from)
    and (p_date_to is null or event_date <= p_date_to)
  group by line_name
  order by total_controles desc;
$$;

create or replace function quality_by_shift(p_date_from date default null, p_date_to date default null)
returns table (
  shift_name text,
  total_controles bigint,
  conformes bigint,
  pct_cumplimiento numeric
)
language sql stable as $$
  select
    coalesce(shift_name, 'Sin asignar') as shift_name,
    count(*) as total_controles,
    count(*) filter (where compliant) as conformes,
    round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
  from control_event_compliance
  where (p_date_from is null or event_date >= p_date_from)
    and (p_date_to is null or event_date <= p_date_to)
  group by shift_name
  order by total_controles desc;
$$;

create or replace function quality_by_employee(p_date_from date default null, p_date_to date default null)
returns table (
  employee_name text,
  total_controles bigint,
  conformes bigint,
  pct_cumplimiento numeric
)
language sql stable as $$
  select
    coalesce(employee_name, 'Sin asignar') as employee_name,
    count(*) as total_controles,
    count(*) filter (where compliant) as conformes,
    round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
  from control_event_compliance
  where (p_date_from is null or event_date >= p_date_from)
    and (p_date_to is null or event_date <= p_date_to)
  group by employee_name
  order by total_controles desc
  limit 10;
$$;

-- Nota: a diferencia de la vista original, acá "remuestreadas"/"liberadas" quedan
-- correctamente acotadas a los remuestreos de desviaciones DENTRO del rango pedido
-- (la vista original no las acotaba por fecha porque no tenía parámetro de fecha).
create or replace function quality_resample_rate(p_date_from date default null, p_date_to date default null)
returns table (
  total_desviaciones bigint,
  remuestreadas bigint,
  liberadas bigint,
  pct_remuestreadas numeric,
  pct_liberadas numeric
)
language sql stable as $$
  with base as (
    select control_event_id
    from control_event_compliance
    where not compliant
      and (p_date_from is null or event_date >= p_date_from)
      and (p_date_to is null or event_date <= p_date_to)
  ),
  resamples as (
    select r.*
    from resample r
    join base b on b.control_event_id = r.control_event_id
  )
  select
    (select count(*) from base) as total_desviaciones,
    (select count(distinct control_event_id) from resamples) as remuestreadas,
    (select count(*) from resamples where released) as liberadas,
    round(
      100.0 * (select count(distinct control_event_id) from resamples)::numeric
        / nullif((select count(*) from base), 0),
      1
    ) as pct_remuestreadas,
    round(
      100.0 * (select count(*) from resamples where released)::numeric
        / nullif((select count(*) from resamples), 0),
      1
    ) as pct_liberadas;
$$;

-- =====================================================================
-- Desviaciones (deviation_*)
-- =====================================================================

create or replace function deviation_detail_range(p_date_from date default null, p_date_to date default null)
returns table (
  control_event_id bigint,
  event_date date,
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
  order by ce.event_date desc, ce.id desc;
$$;

create or replace function deviation_by_parameter_range(p_date_from date default null, p_date_to date default null)
returns table (
  label text,
  unit text,
  desviaciones bigint
)
language sql stable as $$
  select label, unit, count(*) as desviaciones
  from deviation_detail_range(p_date_from, p_date_to)
  group by label, unit
  order by desviaciones desc;
$$;

create or replace function deviation_by_corrective_action_range(p_date_from date default null, p_date_to date default null)
returns table (
  corrective_action text,
  desviaciones bigint
)
language sql stable as $$
  select
    coalesce(corrective_action, 'Sin acción registrada') as corrective_action,
    count(*) as desviaciones
  from deviation_detail_range(p_date_from, p_date_to)
  group by corrective_action
  order by desviaciones desc;
$$;
