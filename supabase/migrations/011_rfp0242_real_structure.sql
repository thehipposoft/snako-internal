-- Snacko Automations — reemplaza el "Control de rotura/peso/envasado" ADIVINADO por la
-- estructura REAL de RFP 0242 (Diego consiguió acceso al Drive real y mandó el archivo).
-- Corre esto DESPUÉS de 010_param_averages_and_deviation_time.sql.
--
-- Qué cambia y por qué: `003_rotura_peso_envasado.sql` había creado DOS formularios
-- provisorios ('PROV-ROTURA-PESO', 'PROV-ENVASADO') con columnas ADIVINADAS, dejado
-- explícito en ese archivo como "hay que reemplazar cuando Diego consiga acceso". La
-- planilla real es UNA sola ('RFP 0242 — Control de producto envasado', Rev 03) y su
-- estructura es bastante distinta de lo que habíamos adivinado:
--
--   - Tiene LOTE y VENCIMIENTO por fila (a diferencia de Sal/Humedad, que no parecen
--     tener un campo de lote propio — esto es relevante para el protocolo por lote una
--     vez que sincronicemos datos reales; ver nota en phase1-source-analysis-and-data-model.md).
--   - El peso neto se mide con VARIAS lecturas por control (hasta 10 pesadas individuales)
--     y la propia planilla ya trae el promedio, desvío estándar y una aprobación (Ok/No Ok)
--     calculados por fila — no un solo valor como habíamos asumido. Guardamos el PROMEDIO
--     como `peso_neto_g` (mismo param_key de antes, para no romper nada que ya lo use) más
--     el desvío y la aprobación como parámetros nuevos.
--   - Rotura crítica/mayor y % rebanado también se miden con 2 lecturas cada uno (mismo
--     patrón de "lectura doble" que ya sospechábamos para SAL — ver `sal_pct_2` en
--     001_initial_schema.sql, ahora con más evidencia de que es una práctica real de
--     Calidad, no una casualidad de un solo formulario). Guardamos el promedio que ya trae
--     la planilla bajo los mismos param_keys que ya teníamos (rotura_critica_pct, etc.).
--   - "Envase abierto longitudinal/transversal" coincide con lo adivinado (Ausencia/Presencia).
--   - "Hermeticidad" y el fechado NO coinciden: la planilla real usa 'Ok'/'No Ok' para
--     ambos (no 'Conforme'/'Ausencia' como habíamos adivinado), y el fechado es UN solo
--     campo combinado ("CONTROL DE FECHADO (LOTE, VTO Y HORA LEGIBLE)"), no tres campos
--     separados (fechado_paquetes/fechado_cajas/encintado_cajas) — esos tres NO EXISTEN
--     en la planilla real, se borran.
--   - No existe "unidades_por_caja" en la planilla real — se borra.

-- =====================================================================
-- 1) Unificar los dos formularios provisorios en el real RFP 0242
-- =====================================================================

-- 'PROV-ROTURA-PESO' pasa a ser el RFP 0242 real (conserva su id, así que los
-- control_event ya cargados con ese control_form_id no se tocan).
update control_form
set rfp_code = 'RFP 0242',
    name = 'Control de producto envasado',
    revision = 'Rev 03'
where rfp_code = 'PROV-ROTURA-PESO';

-- Los control_event que estaban en 'PROV-ENVASADO' pasan al mismo formulario unificado.
update control_event
set control_form_id = (select id from control_form where rfp_code = 'RFP 0242')
where control_form_id = (select id from control_form where rfp_code = 'PROV-ENVASADO');

-- Se borran los parámetros de ambos formularios (se reinsertan abajo con la estructura
-- real) y el formulario 'PROV-ENVASADO', que ya quedó sin control_event apuntándole.
delete from control_form_parameter
where control_form_id in (
  select id from control_form where rfp_code in ('RFP 0242', 'PROV-ENVASADO')
);

delete from control_form where rfp_code = 'PROV-ENVASADO';

-- =====================================================================
-- 2) Parámetros reales de RFP 0242
-- =====================================================================

insert into control_form_parameter (control_form_id, key, label, unit, data_type, sort_order)
select id, x.key, x.label, x.unit, x.data_type, x.sort_order
from control_form, (values
  ('peso_neto_g', 'Peso neto (promedio de las pesadas)', 'g', 'numeric', 1),
  ('peso_neto_desvio', 'Peso neto — desvío estándar', 'g', 'numeric', 2),
  ('peso_neto_aprobacion', 'Peso neto — aprobación', null, 'text', 3),
  ('control_fechado', 'Control de fechado (lote, vto. y hora legible)', null, 'text', 4),
  ('envase_abierto_longitudinal', 'Envase abierto longitudinal', null, 'text', 5),
  ('envase_abierto_transversal', 'Envase abierto transversal', null, 'text', 6),
  ('hermeticidad', 'Hermeticidad', null, 'text', 7),
  ('rotura_rebanada_pct', '% Producto rebanado (promedio)', '%', 'numeric', 8),
  ('rotura_critica_pct', '% Rotura crítica (promedio)', '%', 'numeric', 9),
  ('rotura_mayor_pct', '% Rotura mayor (promedio)', '%', 'numeric', 10)
) as x(key, label, unit, data_type, sort_order)
where control_form.rfp_code = 'RFP 0242'
on conflict (control_form_id, key) do update
  set label = excluded.label, unit = excluded.unit, data_type = excluded.data_type, sort_order = excluded.sort_order;

-- =====================================================================
-- 3) Especificaciones — se corrigen las que estaban mal y se borran las que no existen
-- =====================================================================

delete from parameter_spec where param_key in ('unidades_por_caja', 'fechado_cajas', 'encintado_cajas', 'fechado_paquetes');

-- peso_neto_g y rotura_critica_pct ya tenían spec correcta (67.5/72/76.5 y LSE=25 para
-- Cheddar 72g, del protocolo APT 0201 real) — se dejan igual, solo se reafirman con upsert.
insert into parameter_spec (product_id, param_key, lie, optimo, lse)
select id, x.param_key, x.lie, x.optimo, x.lse
from product, (values
  ('rotura_critica_pct', null::numeric, null::numeric, 25::numeric),
  ('peso_neto_g', 67.5, 72, 76.5)
) as x(param_key, lie, optimo, lse)
where product.name = '72 g Cheddar Saladix'
on conflict (product_id, param_key) do update
  set lie = excluded.lie, optimo = excluded.optimo, lse = excluded.lse;
-- Nota: rotura mayor y rebanada siguen sin límite definido en el protocolo real
-- (celdas en blanco) — se dejan sin fila en parameter_spec a propósito, igual que antes.

insert into parameter_spec (product_id, param_key, expected_text)
select id, x.param_key, x.expected_text
from product, (values
  ('hermeticidad', 'Ok'),                        -- antes decía 'Ausencia', estaba mal
  ('control_fechado', 'Ok'),                      -- reemplaza a 'fechado_paquetes' ('Conforme')
  ('envase_abierto_longitudinal', 'Ausencia'),    -- esto sí coincidía
  ('envase_abierto_transversal', 'Ausencia')      -- esto sí coincidía
) as x(param_key, expected_text)
where product.name = '72 g Cheddar Saladix'
on conflict (product_id, param_key) do update
  set expected_text = excluded.expected_text;
