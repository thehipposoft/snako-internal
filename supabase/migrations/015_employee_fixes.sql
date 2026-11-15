-- Snacko Automations — ajustes de maestro de empleados + normalización más robusta
-- Corre esto DESPUÉS de 014_resolve_staging_to_control_event.sql.
--
-- Contexto (primera corrida real de resolve_stg_quality_event(), 2026-11-13):
-- 12.887 filas resueltas, 499 en cuarentena. De esas 499, casi todas eran 2 casos:
--   - "M. Torres" (329 filas): NO es un empleado nuevo — es la misma persona que ya
--     teníamos como "M.Torres" (sin espacio), mismo patrón que "C.Sagues"/"A.Valdiviezo".
--     La normalización de 014 solo colapsaba espacios dobles, no el espacio después de
--     un punto — se corrige acá mejorando la función, sin tocar el dato real.
--   - "X. Alaniz" (151 filas): este sí es un empleado real que faltaba en la semilla
--     inicial (armada con una lista parcial). Se agrega al maestro.
--   - "v" (1 fila): probable tipeo de una sola vez, se deja en cuarentena a propósito.

-- =====================================================================
-- 1) Empleado real que faltaba
-- =====================================================================

insert into employee (full_name)
values ('X. Alaniz')
on conflict (full_name) do nothing;

-- =====================================================================
-- 2) resolve_stg_quality_event() — normalización mejorada (ignora el espacio
--    después de un punto antes de comparar, además de colapsar espacios dobles)
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

    insert into control_event (
      control_form_id, event_date, event_time, shift_id, line_id,
      primary_product_id, secondary_product_id, employee_id,
      compliant, observations, corrective_action, measurements,
      source_row_ref, data_quality_flags
    ) values (
      v_control_form_id, rec.event_date,
      case when rec.event_time ~ '^\d{1,2}:\d{2}$' then rec.event_time::time else null end,
      v_shift_id, v_line_id, v_primary_product_id, v_secondary_product_id, v_employee_id,
      v_compliant, rec.observations, rec.corrective_action, rec.measurements,
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
