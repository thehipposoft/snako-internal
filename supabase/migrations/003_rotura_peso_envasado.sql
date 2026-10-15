-- Snacko Automations — secciones "Producto terminado" (rotura, peso neto) y "Envasado"
-- del protocolo por lote (APT 0201). Corre esto DESPUÉS de 002_lot_support.sql.
--
-- Fuente de los parámetros y especificaciones: el protocolo real APT 0201 (hoja
-- "PROTOCOLO (demo)" del prototipo Excel) — ver prototipo-protocolo-lote.md.
--
-- IMPORTANTE: Snacko confirmó que rotura/peso neto/envasado están digitalizados en Drive
-- (ver informes-objetivo.md), pero todavía no tenemos acceso a esas planillas ni sus
-- códigos RFP reales. Los `rfp_code` de abajo son PLACEHOLDERS (prefijo PROV-) — hay que
-- reemplazarlos por los códigos reales cuando Diego consiga el acceso, y en ese momento
-- probablemente cambien también las claves de `measurements` según cómo estén armadas
-- esas planillas (no hardcodear más de lo necesario mientras tanto).

-- =====================================================================
-- 1) Formularios y parámetros
-- =====================================================================

insert into control_form (rfp_code, name, revision)
values
  ('PROV-ROTURA-PESO', 'Control de rotura y peso neto (código RFP a confirmar con Snacko)', 'provisorio'),
  ('PROV-ENVASADO', 'Control de envasado (código RFP a confirmar con Snacko)', 'provisorio')
on conflict (rfp_code) do nothing;

insert into control_form_parameter (control_form_id, key, label, unit, data_type, sort_order)
select id, x.key, x.label, x.unit, x.data_type, x.sort_order
from control_form, (values
  ('rotura_critica_pct', '%PF rota crítica', '%', 'numeric', 1),
  ('rotura_mayor_pct', '%PF rota mayor', '%', 'numeric', 2),
  ('rotura_rebanada_pct', '%PF rebanada', '%', 'numeric', 3),
  ('peso_neto_g', 'Peso neto', 'g', 'numeric', 4)
) as x(key, label, unit, data_type, sort_order)
where control_form.rfp_code = 'PROV-ROTURA-PESO'
on conflict (control_form_id, key) do nothing;

insert into control_form_parameter (control_form_id, key, label, unit, data_type, sort_order)
select id, x.key, x.label, x.unit, x.data_type, x.sort_order
from control_form, (values
  ('hermeticidad', 'Hermeticidad', null, 'text', 1),
  ('envase_abierto_longitudinal', 'Envase abierto longitudinal', null, 'text', 2),
  ('envase_abierto_transversal', 'Envase abierto transversal', null, 'text', 3),
  ('fechado_paquetes', 'Fechado en paquetes', null, 'text', 4),
  ('unidades_por_caja', 'Cantidad de unidades por caja', null, 'numeric', 5),
  ('fechado_cajas', 'Fechado de cajas', null, 'text', 6),
  ('encintado_cajas', 'Encintado de cajas', null, 'text', 7)
) as x(key, label, unit, data_type, sort_order)
where control_form.rfp_code = 'PROV-ENVASADO'
on conflict (control_form_id, key) do nothing;

-- =====================================================================
-- 2) Especificaciones — Cheddar 72g (únicas confirmadas hasta ahora)
-- =====================================================================

insert into parameter_spec (product_id, param_key, lie, optimo, lse)
select id, x.param_key, x.lie, x.optimo, x.lse
from product, (values
  ('rotura_critica_pct', null::numeric, null::numeric, 25::numeric),
  ('peso_neto_g', 67.5, 72, 76.5),
  ('unidades_por_caja', null, 30, null)
) as x(param_key, lie, optimo, lse)
where product.name = '72 g Cheddar Saladix'
on conflict (product_id, param_key) do nothing;
-- Nota: rotura mayor y rebanada no tienen límite definido en el protocolo real
-- (celdas en blanco) — se dejan sin fila en parameter_spec a propósito.

insert into parameter_spec (product_id, param_key, expected_text)
select id, x.param_key, x.expected_text
from product, (values
  ('hermeticidad', 'Ausencia'),
  ('envase_abierto_longitudinal', 'Ausencia'),
  ('envase_abierto_transversal', 'Ausencia'),
  ('fechado_paquetes', 'Conforme'),
  ('fechado_cajas', 'Conforme'),
  ('encintado_cajas', 'Conforme')
) as x(param_key, expected_text)
where product.name = '72 g Cheddar Saladix'
on conflict (product_id, param_key) do nothing;

-- =====================================================================
-- 3) Datos de ejemplo SINTÉTICOS — mismo lote 'SN1-1-244'
-- =====================================================================

insert into control_event (
  control_form_id, event_date, event_time, shift_id, line_id,
  primary_product_id, employee_id, measurements, lot_reference, source_row_ref
)
select
  (select id from control_form where rfp_code = 'PROV-ROTURA-PESO'),
  date '2026-10-10',
  (time '06:00' + (gs * interval '25 minutes')),
  (((gs - 1) % 3) + 1)::smallint,
  1,
  (select id from product where name = '72 g Cheddar Saladix'),
  (select id from employee order by random() limit 1),
  jsonb_build_object(
    'rotura_critica_pct', round((random() * 9)::numeric, 2),
    'rotura_mayor_pct', round((random() * 5)::numeric, 2),
    'rotura_rebanada_pct', round((random() * 3)::numeric, 2),
    'peso_neto_g', round((70 + random() * 4)::numeric, 1)
  ),
  'SN1-1-244',
  'seed sintético — prototipo MVP'
from generate_series(1, 15) as gs;

insert into control_event (
  control_form_id, event_date, event_time, shift_id, line_id,
  primary_product_id, employee_id, measurements, lot_reference, source_row_ref
)
select
  (select id from control_form where rfp_code = 'PROV-ENVASADO'),
  date '2026-10-10',
  (time '06:00' + (gs * interval '25 minutes')),
  (((gs - 1) % 3) + 1)::smallint,
  1,
  (select id from product where name = '72 g Cheddar Saladix'),
  (select id from employee order by random() limit 1),
  jsonb_build_object(
    'hermeticidad', 'Ausencia',
    'envase_abierto_longitudinal', 'Ausencia',
    'envase_abierto_transversal', 'Ausencia',
    'fechado_paquetes', 'Conforme',
    'unidades_por_caja', 30,
    'fechado_cajas', 'Conforme',
    'encintado_cajas', 'Conforme'
  ),
  'SN1-1-244',
  'seed sintético — prototipo MVP'
from generate_series(1, 15) as gs;

-- Marca compliant por fila para los dos parámetros numéricos con especificación.
update control_event ce
set compliant = (ce.measurements ->> 'rotura_critica_pct')::numeric <= ps.lse
from parameter_spec ps
where ce.lot_reference = 'SN1-1-244'
  and ce.control_form_id = (select id from control_form where rfp_code = 'PROV-ROTURA-PESO')
  and ps.param_key = 'rotura_critica_pct'
  and ps.product_id = ce.primary_product_id;

update control_event ce
set compliant = (ce.measurements ->> 'peso_neto_g')::numeric between ps.lie and ps.lse
from parameter_spec ps
where ce.lot_reference = 'SN1-1-244'
  and ce.control_form_id = (select id from control_form where rfp_code = 'PROV-ROTURA-PESO')
  and ps.param_key = 'peso_neto_g'
  and ps.product_id = ce.primary_product_id;
