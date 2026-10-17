import { supabaseServer } from "@/lib/supabase/server";

export type ParameterStat = {
  control_form_id: number;
  rfp_code: string;
  form_name: string;
  param_key: string;
  label: string;
  unit: string | null;
  data_type: "numeric" | "text";
  sort_order: number;
  n: number;
  promedio: number | null;
  desvio: number | null;
  minimo: number | null;
  maximo: number | null;
  n_texto: number;
  n_conforme: number;
  n_no_conforme: number;
  lie: number | null;
  optimo: number | null;
  lse: number | null;
  expected_text: string | null;
};

export type LotHeader = {
  lot_reference: string;
  product_name: string | null;
  fecha_desde: string;
  fecha_hasta: string;
  controles: number;
};

export async function getLotData(lote: string) {
  const supabase = supabaseServer();

  const [{ data: header, error: headerError }, { data: stats, error: statsError }] =
    await Promise.all([
      supabase
        .from("lot_summary")
        .select("lot_reference, product_name, fecha_desde, fecha_hasta, controles")
        .eq("lot_reference", lote)
        .maybeSingle<LotHeader>(),
      supabase
        .from("lot_parameter_stats")
        .select(
          "control_form_id, rfp_code, form_name, param_key, label, unit, data_type, sort_order, n, promedio, desvio, minimo, maximo, n_texto, n_conforme, n_no_conforme, lie, optimo, lse, expected_text"
        )
        .eq("lot_reference", lote)
        .order("rfp_code")
        .order("sort_order")
        .returns<ParameterStat[]>(),
    ]);

  if (headerError) throw new Error(`No se pudo leer lot_summary: ${headerError.message}`);
  if (statsError) throw new Error(`No se pudo leer lot_parameter_stats: ${statsError.message}`);

  return { header, stats: stats ?? [] };
}
