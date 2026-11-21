-- Snacko Automations — promedio de Sal (lectura 1+2), desglose por tipo de análisis y
-- filtro por producto en "Promedios por parámetro y línea".
-- Corre esto DESPUÉS de 015_employee_fixes.sql.
--
-- Feedback de Snacko (Florencia + Lucía, 2026-11-20):
--
--  1) Florencia: "Con respecto a la sal, sobre una muestra se hacen dos controles y esos
--     valores nosotros los promediamos [...] es un mismo parámetro que se controla por
--     duplicado." → el dashboard debe mostrar UN solo valor de SAL (%) por control, no
--     "lectura 1" y "lectura 2" separadas.
--
--     Al implementar esto encontramos (y corregimos de paso) un bug que ya existía:
--     `control_form_parameter` tenía la clave 'sal_pct' para "lectura 1" desde
--     001_initial_schema.sql (semilla sintética original, anterior a tener datos reales),
--     pero el nodo de n8n que sincroniza RFP 0241 real guarda las lecturas como
--     'sal_pct_1'/'sal_pct_2' (ver n8n-sync-pilot.md). Como nunca coincidían, la fila
--     "SAL (%) — lectura 1" del panel SOLO mostraba datos sintéticos viejos, nunca datos
--     reales sincronizados — "lectura 2" (clave consistente 'sal_pct_2') sí mezclaba real +
--     sintético. Esto se corrige de raíz calculando el promedio en el momento de resolver
--     cada fila (`resolve_stg_quality_event()`) a partir de las claves reales
--     'sal_pct_1'/'sal_pct_2', guardándolo como 'sal_pct_avg' en measurements, y
--     reemplazando el catálogo de 'sal_pct'+'sal_pct_2' por una sola fila 'sal_pct_avg'.
--     Los valores crudos de lectura 1/2 NO se borran de measurements (quedan ahí por si se
--     necesitan para trazabilidad), simplemente ya no tienen una fila propia en el catálogo.
--
--  2) Lucía: "¿Sería posible agregar la cantidad de controles realizados por tipo de
--     análisis? Me interesa detallar los datos de humedad y control de producto envasado
--     para comparar el cumplimiento entre áreas." → nueva función quality_by_form(), igual
--     patrón que quality_by_line/quality_by_shift/quality_by_employee.
--
--  3) Lucía: "Considero conveniente agregar un filtro [al control de sal] para observar los
--     resultados por tipo de producto elaborado." → se extiende quality_parameter_averages()
--     con un p_product_id opcional (parámetro nuevo al final, con default — compatible con
--     create or replace sin borrar la función).
--
-- NOTA sobre el punto de Lucía de que el filtro por período "hace desaparecer" los
-- controles de producto envasado (RFP 0242): es un problema de DATOS, no de esta función —
-- todo RFP 0242 en la base es la carga sintética de demo de 003_rotura_peso_envasado.sql,
-- fijada en event_date = 2026-10-10, nunca conectada a una sincronización real todavía. No
-- se toca en esta migración; está planteado aparte para decidir con Diego/Snacko.

-- =====================================================================
-- 1) Catálogo: colapsar "lectura 1"/"lectura 2" de Sal en un solo parámetro
-- =====================================================================

update control_form_parameter
set key = 'sal_pct_avg', label = 'SAL (%)'
where control_form_id = (select id from control_form where rfp_code = 'RFP 0241')
  and key = 'sal_pct';

delete from control_form_parameter
where control_form_id = (select id from control_form where rfp_code = 'RFP 0241')
  and key = 'sal_pct_2';

update parameter_spec
set param_key = 'sal_pct_avg'
where param_key = 'sal_pct';

-- =====================================================================
-- 2) resolve_stg_quality_event() — calcula sal_pct_avg a partir de sal_pct_1/sal_pct_2
--    antes de insertar/actualizar control_event. Resto de la función sin cambios
--    respecto de 015_employee_fixes.sql.
-- =====================================================================

create or replace function resolve_stg_quality_event()
returns table (resolved_count integer, quarantined_count integer)
language plpgsql
as $$
declare
  rec record;
  v_control_form_id bigint;
  v_shift_id smallint;
  v_line_id smallint;
  v_primary_product_id bigint;
  v_secondary_product_id bigint;
  v_employee_id bigint;
  v_compliant boolean;
  v_control_event_id bigint;
  v_unresolved_reasons text[];
  v_resolved_count integer := 0;
  v_quarantined_count integer := 0;
  v_lot_ref text;
  v_measurements jsonb;
begin
  for rec in
    select * from stg_quality_event
    where processed_row_hash is distinct from row_hash
  loop
    v_unresolved_reasons := '{}';

    select id into v_control_form_id from control_form where rfp_code = rec.control_form_rfp_code;
    select id into v_shift_id from shift where name = rec.shift_raw;
    select id into v_line_id from production_line where id::text = trim(rec.line_raw);

    if v_control_form_id is null then
      v_unresolved_reasons := v_unresolved_reasons || ('control_form_no_encontrado:' || coalesce(rec.control_form_rfp_code, ''));
    end if;
    if v_shift_id is null then
      v_unresolved_reasons := v_unresolved_reasons || ('turno_no_encontrado:' || coalesce(rec.shift_raw, ''));
    end if;
    if v_line_id is null then
      v_unresolved_reasons := v_unresolved_reasons || ('linea_no_encontrada:' || coalesce(rec.line_raw, ''));
    end if;

    v_primary_product_id := null;
    if rec.product_primary_raw is not null then
      select id into v_primary_product_id from product where name = rec.product_primary_raw;
      if v_primary_product_id is null then
        select id into v_primary_product_id from product
        where regexp_replace(regexp_replace(lower(trim(name)), '\.\s+', '.', 'g'), '\s+', ' ', 'g')
            = regexp_replace(regexp_replace(lower(trim(rec.product_primary_raw)), '\.\s+', '.', 'g'), '\s+', ' ', 'g');
      end if;
      if v_primary_product_id is null then
        v_unresolved_reasons := v_unresolved_reasons || ('producto_no_encontrado:' || rec.product_primary_raw);
      end if;
    end if;

    v_secondary_product_id := null;
    if rec.product_secondary_raw is not null then
      select id into v_secondary_product_id from product where name = rec.product_secondary_raw;
      if v_secondary_product_id is null then
        select id into v_secondary_product_id from product
        where regexp_replace(regexp_replace(lower(trim(name)), '\.\s+', '.', 'g'), '\s+', ' ', 'g')
            = regexp_replace(regexp_replace(lower(trim(rec.product_secondary_raw)), '\.\s+', '.', 'g'), '\s+', ' ', 'g');
      end if;
      if v_secondary_product_id is null then
        v_unresolved_reasons := v_unresolved_reasons || ('producto_secundario_no_encontrado:' || rec.product_secondary_raw);
      end if;
    end if;

    v_employee_id := null;
    if rec.employee_raw is not null then
      select id into v_employee_id from employee where full_name = rec.employee_raw;
      if v_employee_id is null then
        select id into v_employee_id from employee
        where regexp_replace(regexp_replace(lower(trim(full_name)), '\.\s+', '.', 'g'), '\s+', ' ', 'g')
            = regexp_replace(regexp_replace(lower(trim(rec.employee_raw)), '\.\s+', '.', 'g'), '\s+', ' ', 'g');
      end if;
      if v_employee_id is null then
        v_unresolved_reasons := v_unresolved_reasons || ('empleado_no_encontrado:' || rec.employee_raw);
      end if;
    end if;

    if array_length(v_unresolved_reasons, 1) is not null then
      insert into sync_issue (control_form_id, source_row_ref, reason, raw_payload, row_hash)
      values (
        v_control_form_id,
        rec.source_row_ref,
        array_to_string(v_unresolved_reasons, ', '),
        to_jsonb(rec),
        rec.row_hash
      )
      on conflict (source_row_ref) do update
        set reason = excluded.reason,
            raw_payload = excluded.raw_payload,
            row_hash = excluded.row_hash,
            resolved = false,
            created_at = now();

      v_quarantined_count := v_quarantined_count + 1;
      continue;
    end if;

    v_compliant := case upper(coalesce(rec.compliant_raw, ''))
      when 'SI' then true
      when 'NO' then false
      else null
    end;

    -- SAL (RFP 0241): dos lecturas de la misma muestra — Snacko ya las promedia para su
    -- propio análisis, así que el dashboard muestra un solo valor 'sal_pct_avg'. Las
    -- lecturas crudas 'sal_pct_1'/'sal_pct_2' quedan igual en measurements (no se borran).
    v_measurements := rec.measurements;
    if (v_measurements ->> 'sal_pct_1') is not null and (v_measurements ->> 'sal_pct_2') is not null then
      v_measurements := v_measurements || jsonb_build_object(
        'sal_pct_avg',
        round((((v_measurements ->> 'sal_pct_1')::numeric + (v_measurements ->> 'sal_pct_2')::numeric) / 2), 2)
      );
    elsif (v_measurements ->> 'sal_pct_1') is not null then
      v_measurements := v_measurements || jsonb_build_object('sal_pct_avg', (v_measurements ->> 'sal_pct_1')::numeric);
    elsif (v_measurements ->> 'sal_pct_2') is not null then
      v_measurements := v_measurements || jsonb_build_object('sal_pct_avg', (v_measurements ->> 'sal_pct_2')::numeric);
    end if;

    insert into control_event (
      control_form_id, event_date, event_time, shift_id, line_id,
      primary_product_id, secondary_product_id, employee_id,
      compliant, observations, corrective_action, measurements,
      source_row_ref, data_quality_flags
    ) values (
      v_control_form_id, rec.event_date,
      case when rec.event_time ~ '^\d{1,2}:\d{2}$' then rec.event_time::time else null end,
      v_shift_id, v_line_id, v_primary_product_id, v_secondary_product_id, v_employee_id,
      v_compliant, rec.observations, rec.corrective_action, v_measurements,
      rec.source_row_ref, rec.data_quality_flags
    )
    on conflict (source_row_ref) where source_row_ref not like 'seed sintético%' do update
      set control_form_id = excluded.control_form_id,
          event_date = excluded.event_date,
          event_time = excluded.event_time,
          shift_id = excluded.shift_id,
          line_id = excluded.line_id,
          primary_product_id = excluded.primary_product_id,
          secondary_product_id = excluded.secondary_product_id,
          employee_id = excluded.employee_id,
          compliant = excluded.compliant,
          observations = excluded.observations,
          corrective_action = excluded.corrective_action,
          measurements = excluded.measurements,
          data_quality_flags = excluded.data_quality_flags
    returning id into v_control_event_id;

    delete from resample where control_event_id = v_control_event_id;

    if rec.resample_raw is not null and upper(trim(rec.resample_raw)) not in ('', 'N/A', 'NA') then
      for v_lot_ref in
        select trim(x)
        from regexp_split_to_table(rec.resample_raw, '\s*(,|;|/| y | e )\s*') as x
        where trim(x) <> ''
      loop
        insert into resample (control_event_id, lot_reference, released)
        values (
          v_control_event_id,
          v_lot_ref,
          case upper(coalesce(rec.resample_released_raw, ''))
            when 'SI' then true
            when 'NO' then false
            else null
          end
        );
      end loop;
    end if;

    update stg_quality_event
    set processed_at = now(), processed_row_hash = rec.row_hash
    where id = rec.id;

    v_resolved_count := v_resolved_count + 1;
  end loop;

  return query select v_resolved_count, v_quarantined_count;
end;
$$;

-- =====================================================================
-- 3) Backfill: filas ya resueltas (reales) y datos sintéticos existentes
-- =====================================================================

-- 3a) Filas reales de RFP 0241 ya procesadas: se marcan para que el próximo
--     `select * from resolve_stg_quality_event();` las vuelva a tomar y les calcule
--     'sal_pct_avg' (no toca filas de otros formularios).
update stg_quality_event
set processed_row_hash = null
where control_form_rfp_code = 'RFP 0241'
  and processed_row_hash is not null;

-- 3b) Datos sintéticos (lote demo de 002_lot_support.sql y seed de 004_dashboard.sql) que
--     usan las claves 'sal_pct'/'sal_pct_2' directamente en control_event — no pasan por
--     stg_quality_event, así que se actualizan directo acá, una sola vez.
update control_event ce
set measurements = ce.measurements || jsonb_build_object(
  'sal_pct_avg',
  round((((ce.measurements ->> 'sal_pct')::numeric + (ce.measurements ->> 'sal_pct_2')::numeric) / 2), 2)
)
where ce.measurements ? 'sal_pct'
  and ce.measurements ? 'sal_pct_2'
  and not (ce.measurements ? 'sal_pct_avg');

-- =====================================================================
-- 4) Controles por tipo de análisis (quality_by_form) — mismo patrón que
--    quality_by_line/quality_by_shift/quality_by_employee (009_date_range_filters.sql).
-- =====================================================================

create or replace function quality_by_form(p_date_from date default null, p_date_to date default null)
returns table (
  control_form_id bigint,
  rfp_code text,
  form_name text,
  total_controles bigint,
  conformes bigint,
  pct_cumplimiento numeric
)
language sql stable as $$
  select
    control_form_id,
    rfp_code,
    form_name,
    count(*) as total_controles,
    count(*) filter (where compliant) as conformes,
    round(100.0 * count(*) filter (where compliant) / nullif(count(*), 0), 1) as pct_cumplimiento
  from control_event_compliance
  where (p_date_from is null or event_date >= p_date_from)
    and (p_date_to is null or event_date <= p_date_to)
  group by control_form_id, rfp_code, form_name
  order by total_controles desc;
$$;

-- =====================================================================
-- 5) Filtro por producto en "Promedios por parámetro y línea" (Sal, Humedad, etc.)
-- =====================================================================
-- Se agrega p_product_id al FINAL con default null — create or replace es compatible
-- (mismo orden/tipos de los parámetros existentes, misma forma de returns table).

create or replace function quality_parameter_averages(
  p_date_from date default null,
  p_date_to date default null,
  p_product_id bigint default null
)
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
    and (p_product_id is null or cem.primary_product_id = p_product_id)
  group by cem.control_form_id, cf.rfp_code, cf.name, cem.param_key, cem.label, cem.unit, cem.sort_order, cec.line_name
  order by cem.control_form_id, cem.sort_order, cem.param_key, cec.line_name;
$$;

-- =====================================================================
-- Después de aplicar esta migración, correr una vez para recalcular los datos
-- reales de Sal ya sincronizados con la clave nueva:
--
--   select * from resolve_stg_quality_event();
--
-- (Va a mostrar varios miles en resolved_count — son las mismas filas de RFP 0241 ya
-- sincronizadas, reprocesadas solo para agregarles 'sal_pct_avg'; no son filas nuevas.)
