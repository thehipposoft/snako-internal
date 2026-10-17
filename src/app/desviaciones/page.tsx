import Link from "next/link";
import { Suspense } from "react";
import { supabaseServer } from "@/lib/supabase/server";
import { StatTile } from "@/components/StatTile";
import { BarList } from "@/components/BarList";

type ResampleRate = {
  total_desviaciones: number;
  remuestreadas: number;
  liberadas: number;
  pct_remuestreadas: number | null;
  pct_liberadas: number | null;
};

type ByParameter = {
  label: string;
  unit: string | null;
  desviaciones: number;
};

type ByAction = {
  corrective_action: string;
  desviaciones: number;
};

type DeviationRow = {
  control_event_id: number;
  event_date: string;
  label: string;
  unit: string | null;
  value_numeric: number | null;
  lie: number | null;
  lse: number | null;
  line_name: string | null;
  shift_name: string | null;
  employee_name: string | null;
  corrective_action: string | null;
  remuestreado: boolean;
  liberado: boolean | null;
};

async function getDeviationsData() {
  const supabase = supabaseServer();

  const [resample, byParameter, byAction, detail] = await Promise.all([
    supabase.from("quality_resample_rate").select("*").maybeSingle<ResampleRate>(),
    supabase
      .from("deviation_by_parameter")
      .select("*")
      .order("desviaciones", { ascending: false })
      .returns<ByParameter[]>(),
    supabase
      .from("deviation_by_corrective_action")
      .select("*")
      .order("desviaciones", { ascending: false })
      .returns<ByAction[]>(),
    supabase
      .from("deviation_detail")
      .select(
        "control_event_id, event_date, label, unit, value_numeric, lie, lse, line_name, shift_name, employee_name, corrective_action, remuestreado, liberado"
      )
      .order("event_date", { ascending: false })
      .returns<DeviationRow[]>(),
  ]);

  for (const r of [resample, byParameter, byAction, detail]) {
    if (r.error) throw new Error(`No se pudo leer desviaciones: ${r.error.message}`);
  }

  return {
    resample: resample.data,
    byParameter: byParameter.data ?? [],
    byAction: byAction.data ?? [],
    detail: detail.data ?? [],
  };
}

function resampleBadge(row: DeviationRow) {
  if (!row.remuestreado) {
    return (
      <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-medium text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400">
        Sin remuestreo
      </span>
    );
  }
  if (row.liberado) {
    return (
      <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">
        Liberado
      </span>
    );
  }
  return (
    <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700 dark:bg-amber-950 dark:text-amber-400">
      Remuestreado, pendiente
    </span>
  );
}

async function DeviationsContent() {
  const { resample, byParameter, byAction, detail } = await getDeviationsData();

  return (
    <>
      <section className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatTile
          label="Desviaciones"
          value={String(resample?.total_desviaciones ?? 0)}
          tone={resample && resample.total_desviaciones > 0 ? "critical" : "good"}
        />
        <StatTile
          label="% Remuestreadas"
          value={resample?.pct_remuestreadas !== null ? `${resample?.pct_remuestreadas}%` : "—"}
          helpText={`${resample?.remuestreadas ?? 0} de ${resample?.total_desviaciones ?? 0}`}
        />
        <StatTile
          label="% Liberadas tras remuestreo"
          value={resample?.pct_liberadas !== null ? `${resample?.pct_liberadas}%` : "—"}
          helpText={`${resample?.liberadas ?? 0} de ${resample?.remuestreadas ?? 0}`}
        />
        <StatTile
          label="Parámetro más frecuente"
          value={byParameter[0]?.label.replace(" (%)", "").replace(" — lectura 1", "") ?? "—"}
          helpText={byParameter[0] ? `${byParameter[0].desviaciones} desviaciones` : undefined}
        />
      </section>

      <section className="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <div className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
            Desviaciones por parámetro
          </h2>
          <div className="rounded-xl border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-950">
            <BarList
              rows={byParameter.map((r) => ({ label: r.label, value: r.desviaciones }))}
            />
          </div>
        </div>

        <div className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
            Acciones correctivas más comunes
          </h2>
          <div className="rounded-xl border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-950">
            <BarList
              rows={byAction.map((r) => ({
                label: r.corrective_action,
                value: r.desviaciones,
              }))}
              labelWidthClassName="w-full max-w-[55%] sm:max-w-[60%]"
            />
          </div>
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
          Detalle de desviaciones
        </h2>
        <div className="overflow-x-auto rounded-xl border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-[800px] text-left text-sm">
            <thead className="bg-zinc-100 text-zinc-600 dark:bg-zinc-900 dark:text-zinc-400">
              <tr>
                <th className="px-4 py-3 font-medium">Fecha</th>
                <th className="px-4 py-3 font-medium">Parámetro</th>
                <th className="px-4 py-3 font-medium">Medido</th>
                <th className="px-4 py-3 font-medium">Límite</th>
                <th className="px-4 py-3 font-medium">Línea / Turno</th>
                <th className="px-4 py-3 font-medium">Responsable</th>
                <th className="px-4 py-3 font-medium">Acción correctiva</th>
                <th className="px-4 py-3 font-medium">Remuestreo</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
              {detail.map((row) => (
                <tr key={row.control_event_id}>
                  <td className="px-4 py-3 text-zinc-500">{row.event_date}</td>
                  <td className="px-4 py-3 text-zinc-800 dark:text-zinc-200">{row.label}</td>
                  <td className="px-4 py-3 font-medium text-red-600 dark:text-red-400">
                    {row.value_numeric}
                    {row.unit}
                  </td>
                  <td className="px-4 py-3 text-zinc-500">
                    {row.lie ?? "—"}–{row.lse ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-zinc-500">
                    {row.line_name} / {row.shift_name}
                  </td>
                  <td className="px-4 py-3 text-zinc-500">{row.employee_name}</td>
                  <td className="px-4 py-3 text-zinc-500">{row.corrective_action ?? "—"}</td>
                  <td className="px-4 py-3">{resampleBadge(row)}</td>
                </tr>
              ))}
              {detail.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-4 py-6 text-center text-zinc-500">
                    No hay desviaciones registradas.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <p className="text-xs text-zinc-400">
        Calculado en SQL (vistas <code>deviation_*</code>) a partir de los controles
        individuales marcados fuera de especificación — nada hardcodeado en el frontend.
      </p>
    </>
  );
}

function DeviationsSkeleton() {
  return (
    <div className="flex flex-col gap-10">
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-24 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
        ))}
      </div>
      <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <div className="h-40 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
        <div className="h-40 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
      </div>
      <div className="h-64 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
    </div>
  );
}

export default function DeviationsPage() {
  return (
    <div className="min-h-screen bg-zinc-50 font-sans dark:bg-black">
      <main className="mx-auto flex w-full max-w-5xl flex-col gap-10 px-6 py-16 sm:px-10">
        <header className="flex flex-col gap-2">
          <Link href="/" className="text-sm text-emerald-600 dark:text-emerald-400">
            ← Panel general
          </Link>
          <p className="text-sm font-medium uppercase tracking-wide text-emerald-600 dark:text-emerald-400">
            Snacko Automations
          </p>
          <h1 className="text-3xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50">
            Desviaciones y no conformidades
          </h1>
          <p className="text-zinc-600 dark:text-zinc-400">
            Controles de sal y humedad fuera de especificación — datos de ejemplo (sintéticos)
            hasta conectar las planillas reales.
          </p>
        </header>

        <Suspense fallback={<DeviationsSkeleton />}>
          <DeviationsContent />
        </Suspense>
      </main>
    </div>
  );
}
