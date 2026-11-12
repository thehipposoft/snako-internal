-- Snacko Automations — lecturas de Campos Polares por tanque, para una sección aparte
-- del panel general (NO entra en la tabla "Promedios por parámetro y línea" — ver
-- phase1-source-analysis-and-data-model.md §13 sobre por qué esta planilla no tiene
-- columna de línea ni de cumplimiento, y la decisión de Diego de mostrarla aparte).
-- Corre esto DESPUÉS de 012_rfp0224_campos_polares.sql.

create or replace function campos_polares_readings(p_date_from date default null, p_date_to date default null)
returns table (
  event_date date,
  tanque_en_uso numeric,
  tanque_1_cp numeric,
  tanque_2_cp numeric,
  tanque_3_cp numeric,
  tanque_4_cp numeric,
  tanque_5_cp numeric,
  observaciones text,
  employee_name text
)
language sql stable as $$
  select
    ce.event_date,
    (ce.measurements ->> 'tanque_en_uso')::numeric,
    (ce.measurements ->> 'tanque_1_cp')::numeric,
    (ce.measurements ->> 'tanque_2_cp')::numeric,
    (ce.measurements ->> 'tanque_3_cp')::numeric,
    (ce.measurements ->> 'tanque_4_cp')::numeric,
    (ce.measurements ->> 'tanque_5_cp')::numeric,
    ce.observations,
    e.full_name as employee_name
  from control_event ce
  join control_form cf on cf.id = ce.control_form_id
  left join employee e on e.id = ce.employee_id
  where cf.rfp_code = 'RFP 0224'
    and (p_date_from is null or ce.event_date >= p_date_from)
    and (p_date_to is null or ce.event_date <= p_date_to)
  order by ce.event_date desc nulls last;
$$;
