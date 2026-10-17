-- Snacko Automations — vista de desviaciones / no conformidades
-- Corre esto DESPUÉS de 004_dashboard.sql.
--
-- Responde las preguntas de "análisis de desviaciones" del brief original: qué parámetro
-- concentra más problemas, qué acciones correctivas son más comunes, qué % de desviaciones
-- se remuestrea y con qué frecuencia el remuestreo termina liberado.

-- =====================================================================
-- 1) Acción correctiva sintética para las desviaciones del dashboard general
-- =====================================================================
-- (los datos del lote de demo SN1-1-244 no tienen desviaciones a propósito, así que esto
-- solo toca los controles generales sembrados en 004_dashboard.sql)

update control_event ce
set corrective_action = (array[
  'Se recalibró el equipo y se repitió el control',
  'Se notificó a Producción y se intensificó la frecuencia de muestreo',
  'Se ajustó el proceso y se solicitó remuestreo',
  'Se descartó el lote parcial afectado',
  'Se derivó a Calidad para revisión del lote completo'
])[1 + floor(random() * 5)::int]
where ce.compliant = false
  and ce.lot_reference is null
  and ce.corrective_action is null;

-- =====================================================================
-- 2) Vistas
-- =====================================================================

create view deviation_detail as
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
order by ce.event_date desc, ce.id desc;

create view deviation_by_parameter as
select
  label,
  unit,
  count(*) as desviaciones
from deviation_detail
group by label, unit
order by desviaciones desc;

create view deviation_by_corrective_action as
select
  coalesce(corrective_action, 'Sin acción registrada') as corrective_action,
  count(*) as desviaciones
from deviation_detail
group by corrective_action
order by desviaciones desc;
