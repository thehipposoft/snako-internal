-- Snacko Automations — paso stg_quality_event -> control_event (resolución de FKs)
-- Corre esto DESPUÉS de 013_campos_polares_por_tanque.sql.
--
-- Qué resuelve: hasta ahora, n8n deja las filas limpias en `stg_quality_event` con los
-- valores todavía en texto crudo (product_primary_raw, employee_raw, etc.) — nunca llegan
-- a `control_event` con los FKs reales. Este es exactamente el paso que quedó pendiente
-- desde el pilot de n8n (ver n8n-sync-pilot.md), ahora que el sync corre contra datos reales.
--
-- Importante: para cuando una fila llega a `stg_quality_event`, n8n YA la validó (fecha
-- parseable, turno conocido, línea numérica, medición numérica donde corresponde) — todo
-- lo que falla esas validaciones queda en `sync_issue` directamente, nunca llega acá. Lo
-- único que n8n NO puede validar es si el texto de producto/empleado existe en nuestras
-- tablas maestras (`product`/`employee`) — eso es precisamente lo que resuelve esta función.
--
-- Decisión de diseño: si un producto o empleado no matchea contra el maestro, la fila se
-- manda a `sync_issue` para revisión humana en vez de crear automáticamente una fila nueva
-- en `product`/`employee`. Esto evita que un typo (ej. "160  g Snacko" con doble espacio,
-- ya confirmado como typo real recurrente) termine creando un producto fantasma. Si en el
-- día a día aparecen muchos productos/empleados genuinamente nuevos y este comportamiento
-- resulta molesto, se puede cambiar a "auto-crear" más adelante — ver nota al final.

-- =====================================================================
-- 1) Columnas de soporte
-- =====================================================================

-- stg_quality_event ya tenía `processed_at` (reservado para este paso desde 007). Le
-- sumamos `processed_row_hash`: guarda qué row_hash tenía la fila la última vez que se
-- intentó resolver. Si el operador edita una fila ya sincronizada (y por lo tanto su
-- row_hash cambia en la próxima corrida de n8n), esta columna deja de coincidir con el
-- row_hash actual y la fila se vuelve a procesar — sin esto, una corrección posterior
-- del operador nunca se reflejaría en control_event.
alter table stg_quality_event add column if not exists processed_row_hash text;

create index if not exists stg_quality_event_needs_resolution_idx
  on stg_quality_event (id)
  where processed_row_hash is distinct from row_hash;

-- control_event necesita una restricción unique sobre source_row_ref para poder hacer
-- upsert (igual que ya tienen stg_quality_event y sync_issue). OJO: los datos sintéticos
-- de 002/003/004 reutilizan el mismo source_row_ref literal en muchas filas a propósito
-- ("seed sintético — ...") — por eso la unicidad se aplica solo a las filas reales
-- (las que vienen de la sincronización, con formato "RFP 0241:123"), vía índice parcial.
create unique index if not exists control_event_source_row_ref_key
  on control_event (source_row_ref)
  where source_row_ref not like 'seed sintético%';

-- =====================================================================
-- 2) Función de resolución
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

    -- control_form y shift y línea: n8n ya los deja siempre válidos (ver nota arriba),
    -- así que si estos no resuelven es un problema de catálogo, no de esta fila puntual.
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

    -- Producto primario: match exacto primero, después case/espacios-insensible.
    v_primary_product_id := null;
    if rec.product_primary_raw is not null then
      select id into v_primary_product_id from product where name = rec.product_primary_raw;
      if v_primary_product_id is null then
        select id into v_primary_product_id from product
        where regexp_replace(lower(trim(name)), '\s+', ' ', 'g')
            = regexp_replace(lower(trim(rec.product_primary_raw)), '\s+', ' ', 'g');
      end if;
      if v_primary_product_id is null then
        v_unresolved_reasons := v_unresolved_reasons || ('producto_no_encontrado:' || rec.product_primary_raw);
      end if;
    end if;

    -- Producto secundario: mismo criterio, pero es opcional (no todas las filas tienen).
    v_secondary_product_id := null;
    if rec.product_secondary_raw is not null then
      select id into v_secondary_product_id from product where name = rec.product_secondary_raw;
      if v_secondary_product_id is null then
        select id into v_secondary_product_id from product
        where regexp_replace(lower(trim(name)), '\s+', ' ', 'g')
            = regexp_replace(lower(trim(rec.product_secondary_raw)), '\s+', ' ', 'g');
      end if;
      if v_secondary_product_id is null then
        v_unresolved_reasons := v_unresolved_reasons || ('producto_secundario_no_encontrado:' || rec.product_secondary_raw);
      end if;
    end if;

    -- Empleado: mismo criterio que producto.
    v_employee_id := null;
    if rec.employee_raw is not null then
      select id into v_employee_id from employee where full_name = rec.employee_raw;
      if v_employee_id is null then
        select id into v_employee_id from employee
        where regexp_replace(lower(trim(full_name)), '\s+', ' ', 'g')
            = regexp_replace(lower(trim(rec.employee_raw)), '\s+', ' ', 'g');
      end if;
      if v_employee_id is null then
        v_unresolved_reasons := v_unresolved_reasons || ('empleado_no_encontrado:' || rec.employee_raw);
      end if;
    end if;

    -- Si algo no resolvió, a cuarentena — y NO se marca processed_row_hash, para que se
    -- reintente solo en la próxima corrida (por si mientras tanto alguien agrega el
    -- producto/empleado que faltaba al maestro).
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

    -- Remuestreos: "N° remuestreo" puede traer más de un lote en el mismo texto
    -- (ej. "261 y 262") — se separa en filas individuales de `resample`. Se borran las
    -- anteriores de este control_event antes de reinsertar, por si esto es un reproceso
    -- de una fila editada (evita duplicar remuestreos en cada corrida).
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

-- Nota sobre la alternativa "auto-crear producto/empleado nuevo en vez de poner en
-- cuarentena": si en la práctica aparecen muchos productos/empleados genuinamente nuevos
-- (no typos) y la cuarentena resulta molesta, se puede cambiar el bloque de arriba para
-- que, en vez de sumar a v_unresolved_reasons, haga `insert into product(name) values
-- (rec.product_primary_raw) returning id into v_primary_product_id` (ídem employee). Se
-- dejó en modo cuarentena por ahora porque es más seguro mientras no está confirmada la
-- lista completa de productos/personal (ver pregunta #3 en phase1-source-analysis-and-data-model.md).
