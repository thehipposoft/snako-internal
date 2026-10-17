-- Snacko Automations — agrega conteo de "N° controles NC" a lot_parameter_stats
-- Corre esto DESPUÉS de 005_deviations.sql.
--
-- El protocolo real (APT 0201) tiene una columna "N° controles NC" — cuántas lecturas
-- individuales del lote cayeron fuera de L.I.E./L.S.E. (no el promedio, cada lectura).
-- La vista hasta ahora no la calculaba; hace falta para la exportación a Excel.

drop view if exists lot_parameter_stats;

create view lot_parameter_stats as
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
  count(*) filter (
    where cem.data_type = 'numeric'
      and (
        (ps.lie is not null and cem.value_numeric < ps.lie)
        or (ps.lse is not null and cem.value_numeric > ps.lse)
      )
  ) as n_no_conforme,
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
