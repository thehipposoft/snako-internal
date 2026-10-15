-- Snacko Automations — esquema inicial (Supabase / Postgres)
-- Basado en phase1-source-analysis-and-data-model.md e informes-objetivo.md del proyecto.
-- Pensado para correr tal cual en el SQL Editor de Supabase.

-- =====================================================================
-- Maestros
-- =====================================================================

create table production_line (
  id          smallint primary key,
  name        text not null
);
insert into production_line (id, name) values (1, 'Línea 1'), (2, 'Línea 2');

create table shift (
  id          smallint primary key,
  code        text not null unique,   -- 'mañana' | 'tarde' | 'noche' (normalizado, minúsculas)
  name        text not null           -- 'Mañana' | 'Tarde' | 'Noche' (para mostrar)
);
insert into shift (id, code, name) values
  (1, 'mañana', 'Mañana'),
  (2, 'tarde', 'Tarde'),
  (3, 'noche', 'Noche');

create table employee (
  id          bigint generated always as identity primary key,
  full_name   text not null unique,   -- tal como aparece en REALIZO
  area        text                    -- 'calidad' | 'produccion' — confirmar con Snacko (sección 3 del informe mensual)
);
-- Semilla parcial a partir de RFP 0241 / 0243 (lista DATOS!REALIZO) — completar cuando se confirme el resto.
insert into employee (full_name) values
  ('O. Guerra'), ('D. Quiroga'), ('M. Carrazán'), ('R. Diaz'), ('R. Carrazán'),
  ('C. Sanchez'), ('P. Yonar'), ('G. Marín'), ('R. Quiroga'), ('L. Gonzalez'),
  ('G. Balacco'), ('J. Yapura'), ('S. Enriquez'), ('M.Torres'), ('C.Sagues'),
  ('A.Valdiviezo'), ('J. Rodriguez'), ('L. Lobo'), ('V. Sosa'), ('S. Bautista');

create table product (
  id          bigint generated always as identity primary key,
  name        text not null unique,   -- tal como aparece en GRAMAJE, normalizado (sin dobles espacios)
  gramaje_g   numeric,                -- extraído del nombre cuando es posible, nullable si no aplica
  brand       text,                   -- 'Saladix' | 'Snacko' | 'Yari' | 'Pormás' — derivado del nombre
  active      boolean not null default true
);
-- Semilla a partir de DATOS!GRAMAJE (idéntica en RFP 0241 y 0243).
insert into product (name) values
  ('130 g Clásica Saladix'), ('80 g Clásica Saladix'), ('72 g Cheddar Saladix'),
  ('72 g Crema&cebolla Saladix'), ('800 g Snacko'), ('500 g Snacko'), ('370 g Snacko'),
  ('200 g Snacko'), ('160 g Snacko'), ('120 g Snacko'), ('80 g Snacko'), ('40 g Snacko'),
  ('25 g Snacko'), ('70 g Jamón serrano Snacko'), ('115 g Jamón serrano Snacko'),
  ('115 g Cebolla y crema Snacko'), ('115 g Cheddar Snacko'), ('115 g Limón Snacko'),
  ('115 g Ketchup Snacko'), ('115 g Picante Snacko'), ('110 g Corte americano Snacko'),
  ('1 kg Pay Pormás'), ('65 g Pay Snacko'), ('500 g Yari'), ('42 g Yari'), ('70 g Sin sal Snacko');

-- =====================================================================
-- Formularios de control (uno por RFP/APT) y sus parámetros
-- =====================================================================

create table control_form (
  id              bigint generated always as identity primary key,
  rfp_code        text not null unique,    -- 'RFP 0241', 'RFP 0243', ...
  name            text not null,           -- 'Control de sal', 'Control de humedad', ...
  revision        text,
  effective_date  date
);
insert into control_form (rfp_code, name, revision) values
  ('RFP 0241', 'Control de sal', 'Rev 02'),
  ('RFP 0243', 'Control de humedad y freidor', 'Rev 05');
-- Pendiente: agregar rotura, peso neto y control de envasado cuando tengamos acceso a esas planillas
-- (ver informes-objetivo.md, sección "Próximo paso").

-- Qué parámetros trae cada formulario dentro de `measurements` (jsonb) — documenta la forma del
-- JSON sin forzar una columna nueva por parámetro, y permite que el dashboard/reporte se arme
-- genéricamente a partir de esta tabla en vez de código a medida por formulario.
create table control_form_parameter (
  id              bigint generated always as identity primary key,
  control_form_id bigint not null references control_form(id),
  key             text not null,      -- clave dentro de measurements, ej. 'sal_pct'
  label           text not null,      -- 'SAL (%)'
  unit            text,
  data_type       text not null default 'numeric',  -- 'numeric' | 'text'
  sort_order      smallint not null default 0,
  unique (control_form_id, key)
);
insert into control_form_parameter (control_form_id, key, label, unit, sort_order)
select id, 'sal_pct', 'SAL (%) — lectura 1', '%', 1 from control_form where rfp_code = 'RFP 0241';
insert into control_form_parameter (control_form_id, key, label, unit, sort_order)
select id, 'sal_pct_2', 'SAL (%) — lectura 2 (confirmar significado con Calidad)', '%', 2 from control_form where rfp_code = 'RFP 0241';

insert into control_form_parameter (control_form_id, key, label, unit, sort_order)
select id, x.key, x.label, x.unit, x.sort_order
from control_form, (values
  ('humedad_pct', 'HUMEDAD (%)', '%', 1),
  ('codigo_equipo', 'CÓDIGO EQUIPO', null, 2),
  ('t_freidor', 'T° FREIDOR', '°C', 3),
  ('velocidad_cinta', 'VELOCIDAD CINTA DE FREIDOR', null, 4),
  ('control_visual_color', 'CONTROL VISUAL DE COLOR', null, 5),
  ('pf_manchadas_pct', '%PF MANCHADAS', '%', 6),
  ('pf_verdes_pct', '%PF VERDES', '%', 7),
  ('pf_puntos_oscuros_pct', '%PF PUNTOS OSCUROS', '%', 8)
) as x(key, label, unit, sort_order)
where control_form.rfp_code = 'RFP 0243';

-- =====================================================================
-- Especificaciones por producto y parámetro (L.I.E. / Óptimo / L.S.E.)
-- =====================================================================
-- Esta es la tabla que faltaba y que encontramos documentada dentro del protocolo por lote
-- (APT 0201) — ver informes-objetivo.md. De momento solo tenemos los valores de Cheddar 72g;
-- hay que pedirle a Snacko la tabla completa para el resto de los productos.

create table parameter_spec (
  id          bigint generated always as identity primary key,
  product_id  bigint references product(id),   -- null = aplica a todos los productos
  param_key   text not null,     -- mismo vocabulario que control_form_parameter.key / measurements
  lie         numeric,           -- límite inferior especificado (null = sin mínimo)
  optimo      numeric,
  lse         numeric,           -- límite superior especificado (null = sin máximo)
  expected_text text,            -- para parámetros categóricos ('Conforme', 'Ausencia', etc.)
  unique (product_id, param_key)
);

-- Semilla: valores reales tomados del protocolo APT 0201 para Cheddar 72g (único producto confirmado hasta ahora).
insert into parameter_spec (product_id, param_key, lie, optimo, lse)
select id, x.param_key, x.lie, x.optimo, x.lse
from product, (values
  ('humedad_pct', 0.8, 1.3, 1.6),
  ('sal_pct', 0.9, null, 1.8),
  ('pf_manchadas_pct', null, null, 10),
  ('pf_verdes_pct', null, null, 4),
  ('pf_puntos_oscuros_pct', null, null, 20)
) as x(param_key, lie, optimo, lse)
where product.name = '72 g Cheddar Saladix';

insert into parameter_spec (product_id, param_key, expected_text)
select id, 'control_visual_color', 'Conforme'
from product where product.name = '72 g Cheddar Saladix';

-- =====================================================================
-- Controles (un registro = una fila de la pestaña "Registro")
-- =====================================================================

create table control_event (
  id                  bigint generated always as identity primary key,
  control_form_id     bigint not null references control_form(id),
  event_date          date,                 -- null permitido: fechas no parseables quedan en null + flag
  event_time          time,
  shift_id            smallint references shift(id),
  line_id             smallint references production_line(id),
  primary_product_id  bigint references product(id),
  secondary_product_id bigint references product(id),  -- línea corriendo 2 productos a la vez
  employee_id         bigint references employee(id),
  compliant           boolean,              -- SI/NO/blank tal como lo ingresó el operador
  observations        text,
  corrective_action    text,
  measurements         jsonb not null default '{}'::jsonb,
  source_row_ref       text,                -- ej. 'RFP0241 Registro fila 1024', para trazabilidad
  data_quality_flags    text[] not null default '{}',  -- 'unparsed_date','outlier_value','stale_validation', etc.
  ingested_at           timestamptz not null default now()
);

create index control_event_form_date_idx on control_event (control_form_id, event_date);
create index control_event_product_idx on control_event (primary_product_id);
create index control_event_measurements_gin on control_event using gin (measurements);
create index control_event_flags_idx on control_event using gin (data_quality_flags);

create table resample (
  id                bigint generated always as identity primary key,
  control_event_id  bigint not null references control_event(id),
  lot_reference     text not null,     -- valor crudo de "N° remuestreo", ej. '466' o '261 y 262' ya separado en filas
  released          boolean,
  resolved_at        timestamptz,
  notes              text
);

-- Cola de revisión para lo que la sincronización no pudo normalizar con confianza
-- (fechas ilegibles, valores fuera de catálogo, outliers estadísticos, etc.)
create table sync_issue (
  id            bigint generated always as identity primary key,
  control_form_id bigint references control_form(id),
  source_row_ref  text,
  reason          text not null,
  raw_payload     jsonb,
  resolved        boolean not null default false,
  created_at      timestamptz not null default now()
);

-- =====================================================================
-- Vista de ejemplo: estadísticas por lote/producto (el cálculo que hoy se
-- hace a mano en el protocolo APT 0201) — ver prototipo-protocolo-lote.md
-- =====================================================================
-- NOTA: esto asume que vamos a poder identificar "lote" a partir de los datos
-- (hoy control_event no tiene columna de lote explícita porque las planillas
-- de sal/humedad no la traen — confirmar con Snacko cómo se correlaciona un
-- lote con fecha/línea/producto antes de implementar esta vista en serio).
--
-- create view lot_parameter_stats as
-- select
--   primary_product_id,
--   (measurements->>'<param_key>')::numeric as valor
--   -- agrupar por lote cuando sepamos cómo derivarlo
-- from control_event;
