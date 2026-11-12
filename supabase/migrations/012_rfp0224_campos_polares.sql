-- Snacko Automations — estructura real de RFP 0224 (Control de campos polares en
-- tanques externos). Corre esto DESPUÉS de 011_rfp0242_real_structure.sql.
--
-- IMPORTANTE — esto deja el formulario y sus parámetros listos para recibir datos
-- (vía n8n más adelante), pero A PROPÓSITO no:
--   - crea datos sintéticos de ejemplo,
--   - lo conecta a la tabla "Promedios por parámetro y línea" del dashboard.
-- Motivo: esta planilla tiene una forma MUY distinta a las demás (Sal, Humedad,
-- Envasado), que rompe los supuestos con los que está armado el resto del sistema:
--   1. No tiene LINEA, TURNO ni GRAMAJE (producto) por fila — es un control de
--      EQUIPO/TANQUE (hasta 5 tanques de aceite), no de línea de producción. No hay
--      forma de que encaje en una columna "Línea 1"/"Línea 2" como pidió Snacko.
--   2. No tiene "¿Cumple con las especificaciones?" — no hay juicio de cumplimiento
--      por fila, así que quedaría afuera de `control_event_compliance` (que exige
--      `compliant is not null`) y por lo tanto de `quality_overview`/KPIs generales.
--   3. Es quincenal (32 filas en ~2 años, contra miles de las otras) — no tiene sentido
--      mostrarlo con la misma cadencia/gráficos que el resto.
-- Ver pregunta para Diego en phase1-source-analysis-and-data-model.md sobre cómo
-- presentar esto (probablemente una sección aparte "por tanque", no la tabla por línea).

insert into control_form (rfp_code, name, revision)
values ('RFP 0224', 'Control de campos polares en tanques externos', 'Rev 04')
on conflict (rfp_code) do nothing;

-- Hasta 5 tanques, cada uno con su % de compuestos polares (CP) y su N° de equipo.
-- 'N/A' en la planilla (tanque vacío/no usado) se normaliza a NULL en la ingesta, no es
-- un dato faltante por error — ver OBSERVACIONES de la planilla real.
insert into control_form_parameter (control_form_id, key, label, unit, data_type, sort_order)
select id, x.key, x.label, x.unit, x.data_type, x.sort_order
from control_form, (values
  ('fecha_ingreso', 'Fecha de ingreso del aceite en uso', null, 'text', 1),
  ('tanque_en_uso', 'Tanque en uso', null, 'numeric', 2),
  ('tanque_1_cp', 'Tanque 1 — Compuestos polares', '%', 'numeric', 3),
  ('tanque_1_equipo', 'Tanque 1 — N° de equipo', null, 'numeric', 4),
  ('tanque_2_cp', 'Tanque 2 — Compuestos polares', '%', 'numeric', 5),
  ('tanque_2_equipo', 'Tanque 2 — N° de equipo', null, 'numeric', 6),
  ('tanque_3_cp', 'Tanque 3 — Compuestos polares', '%', 'numeric', 7),
  ('tanque_3_equipo', 'Tanque 3 — N° de equipo', null, 'numeric', 8),
  ('tanque_4_cp', 'Tanque 4 — Compuestos polares', '%', 'numeric', 9),
  ('tanque_4_equipo', 'Tanque 4 — N° de equipo', null, 'numeric', 10),
  ('tanque_5_cp', 'Tanque 5 — Compuestos polares', '%', 'numeric', 11),
  ('tanque_5_equipo', 'Tanque 5 — N° de equipo', null, 'numeric', 12)
) as x(key, label, unit, data_type, sort_order)
where control_form.rfp_code = 'RFP 0224'
on conflict (control_form_id, key) do update
  set label = excluded.label, unit = excluded.unit, data_type = excluded.data_type, sort_order = excluded.sort_order;

-- Sin parameter_spec todavía: no tenemos un umbral de CP% confirmado por Snacko (en la
-- industria se suele usar ~25% como límite de descarte del aceite, pero no está
-- confirmado acá — no lo inventamos).
