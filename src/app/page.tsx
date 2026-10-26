import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { supabaseServer } from "@/lib/supabase/server";
import { StatTile } from "@/components/StatTile";
import { BarList } from "@/components/BarList";
import { TrendChart } from "@/components/TrendChart";
import { DateRangeFilter } from "@/components/DateRangeFilter";
import { rpcList, rpcSingle } from "@/lib/supabase/rpc";

export const metadata: Metadata = {
  title: "Panel de control de calidad · Snacko Calidad",
};

type Overview = {
  total_controles: number;
  conformes: number;
  desviaciones: number;
  pct_cumplimiento: number | null;
};

type TrendRow = {
  semana: string;
  total_controles: number;
  conformes: number;
  pct_cumplimiento: number | null;
};

type GroupRow = {
  line_name?: string;
  shift_name?: string;
  employee_name?: string;
  total_controles: number;
  conformes: number;
  pct_cumplimiento: number | null;
};

type ResampleRate = {
  total_desviaciones: number;
  remuestreadas: number;
  liberadas: number;
  pct_remuestreadas: number | null;
  pct_liberadas: number | null;
};

type ParamAverageRow = {
  control_form_id: number;
  rfp_code: string;
  form_name: string;
  param_key: string;
  label: string;
  unit: string | null;
  sort_order: number;
  line_name: string;
  avg_value: number;
  n: number;
};

// Solo deja pasar fechas con forma YYYY-MM-DD (lo que manda un <input type="date">) —
// cualquier otra cosa en el query string se ignora en vez de romper la consulta a Supabase.
function sanitizeDate(value: string | undefined): string | null {
  if (!value) return null;
  return /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}

async function getDashboardData(desde: string | null, hasta: string | null) {
  const supabase = supabaseServer();
  const range = { p_date_from: desde, p_date_to: hasta };

  const [overview, trend, byLine, byShift, byEmployee, resample, paramAverages] =
    await Promise.all([
      rpcSingle<Overview>(supabase, "quality_overview", range),
      rpcList<TrendRow>(supabase, "quality_trend_weekly", range),
      rpcList<GroupRow>(supabase, "quality_by_line", range),
      rpcList<GroupRow>(supabase, "quality_by_shift", range),
      rpcList<GroupRow>(supabase, "quality_by_employee", range),
      rpcSingle<ResampleRate>(supabase, "quality_resample_rate", range),
      rpcList<ParamAverageRow>(supabase, "quality_parameter_averages", range),
    ]);

  return { overview, trend, byLine, byShift, byEmployee, resample, paramAverages };
}

// Agrupa las filas (una por parámetro × línea) en una tabla pivot: una fila por
// parámetro, una columna por línea. "Línea 1"/"Línea 2" siempre van primero (en ese
// orden); cualquier otro valor de línea (o "Sin asignar") queda al final, alfabético.
function pivotParamAverages(rows: ParamAverageRow[]) {
  const lineRank = (name: string) => (name === "Línea 1" ? 0 : name === "Línea 2" ? 1 : 2);
  const lines = Array.from(new Set(rows.map((r) => r.line_name))).sort(
    (a, b) => lineRank(a) - lineRank(b) || a.localeCompare(b)
  );

  const values = new Map<string, Map<string, number>>();
  const meta = new Map<string, { label: string; unit: string | null }>();
  const order: string[] = [];

  for (const r of rows) {
    const key = `${r.control_form_id}:${r.param_key}`;
    if (!meta.has(key)) {
      meta.set(key, { label: r.label, unit: r.unit });
      order.push(key);
    }
    if (!values.has(key)) values.set(key, new Map());
    values.get(key)!.set(r.line_name, r.avg_value);
  }

  const paramRows = order.map((key) => ({
    key,
    ...meta.get(key)!,
    values: values.get(key)!,
  }));

  return { lines, paramRows };
}

function badgeTone(pct: number | null): "good" | "warning" | "critical" {
  if (pct === null) return "warning";
  if (pct >= 95) return "good";
  if (pct >= 85) return "warning";
  return "critical";
}

function formatWeek(iso: string) {
  const d = new Date(iso + "T00:00:00");
  return d.toLocaleDateString("es-AR", { day: "2-digit", month: "2-digit" });
}

async function DashboardContent({
  desde,
  hasta,
}: {
  desde: string | null;
  hasta: string | null;
}) {
  const { overview, trend, byLine, byShift, byEmployee, resample, paramAverages } =
    await getDashboardData(desde, hasta);

  const { lines, paramRows } = pivotParamAverages(paramAverages);

  const trendPoints = trend.map((t) => ({
    label: `Semana del ${formatWeek(t.semana)}`,
    pct: t.pct_cumplimiento ?? 0,
    n: t.total_controles,
  }));

  return (
    <>
      <section className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatTile label="Controles totales" value={String(overview?.total_controles ?? 0)} />
        <StatTile
          label="% Cumplimiento"
          value={overview?.pct_cumplimiento !== null ? `${overview?.pct_cumplimiento}%` : "—"}
          tone={badgeTone(overview?.pct_cumplimiento ?? null)}
        />
        <StatTile
          label="Desviaciones"
          value={String(overview?.desviaciones ?? 0)}
          tone={overview && overview.desviaciones > 0 ? "critical" : "good"}
        />
        <StatTile
          label="Remuestreos liberados"
          value={resample?.pct_liberadas !== null ? `${resample?.pct_liberadas}%` : "—"}
          helpText={`${resample?.liberadas ?? 0} de ${resample?.remuestreadas ?? 0} remuestreos`}
        />
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
          Cumplimiento semanal
        </h2>
        <div className="rounded-xl border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-950">
          <TrendChart data={trendPoints} />
        </div>
      </section>

      <section className="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <div className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">Por línea</h2>
          <div className="rounded-xl border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-950">
            <BarList
              rows={byLine.map((r) => ({
                label: r.line_name ?? "Sin asignar",
                value: r.total_controles,
                badgeText: r.pct_cumplimiento !== null ? `${r.pct_cumplimiento}%` : "—",
                badgeTone: badgeTone(r.pct_cumplimiento),
              }))}
            />
          </div>
        </div>

        <div className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">Por turno</h2>
          <div className="rounded-xl border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-950">
            <BarList
              rows={byShift.map((r) => ({
                label: r.shift_name ?? "Sin asignar",
                value: r.total_controles,
                badgeText: r.pct_cumplimiento !== null ? `${r.pct_cumplimiento}%` : "—",
                badgeTone: badgeTone(r.pct_cumplimiento),
              }))}
            />
          </div>
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
          Promedios por parámetro y línea
        </h2>
        <div className="overflow-x-auto rounded-xl border border-zinc-200 dark:border-zinc-800">
          <table className="w-full min-w-[480px] text-left text-sm">
            <thead className="bg-zinc-100 text-zinc-600 dark:bg-zinc-900 dark:text-zinc-400">
              <tr>
                <th className="px-4 py-3 font-medium">Parámetro</th>
                {lines.map((line) => (
                  <th key={line} className="px-4 py-3 font-medium">
                    {line}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
              {paramRows.map((row) => (
                <tr key={row.key}>
                  <td className="px-4 py-3 text-zinc-800 dark:text-zinc-200">{row.label}</td>
                  {lines.map((line) => (
                    <td key={line} className="px-4 py-3 tabular-nums text-zinc-500">
                      {row.values.has(line)
                        ? `${row.values.get(line)}${row.unit ?? ""}`
                        : "—"}
                    </td>
                  ))}
                </tr>
              ))}
              {paramRows.length === 0 && (
                <tr>
                  <td colSpan={1 + lines.length} className="px-4 py-6 text-center text-zinc-500">
                    No hay datos para el período seleccionado.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-zinc-400">
          Promedio de cada parámetro medido durante el período filtrado, por línea de
          producción.
        </p>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
          Controles por responsable
        </h2>
        <div className="overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
          <table className="w-full text-left text-sm">
            <thead className="bg-zinc-100 text-zinc-600 dark:bg-zinc-900 dark:text-zinc-400">
              <tr>
                <th className="px-4 py-3 font-medium">Responsable</th>
                <th className="px-4 py-3 font-medium">Controles</th>
                <th className="px-4 py-3 font-medium">% Cumplimiento</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
              {byEmployee.map((row) => (
                <tr key={row.employee_name}>
                  <td className="px-4 py-3 text-zinc-800 dark:text-zinc-200">
                    {row.employee_name}
                  </td>
                  <td className="px-4 py-3 tabular-nums text-zinc-500">{row.total_controles}</td>
                  <td className="px-4 py-3 tabular-nums text-zinc-500">
                    {row.pct_cumplimiento !== null ? `${row.pct_cumplimiento}%` : "—"}
                  </td>
                </tr>
              ))}
              {byEmployee.length === 0 && (
                <tr>
                  <td colSpan={3} className="px-4 py-6 text-center text-zinc-500">
                    No hay datos todavía.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <p className="text-xs text-zinc-400">
        Todo lo de arriba se calcula en SQL (funciones <code>quality_*</code>) a partir de los
        controles individuales — nada hardcodeado en el frontend.
      </p>
    </>
  );
}

function DashboardSkeleton() {
  return (
    <div className="flex flex-col gap-10">
      <div className="h-16 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-24 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
        ))}
      </div>
      <div className="h-48 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
      <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
        <div className="h-40 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
        <div className="h-40 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
      </div>
    </div>
  );
}

type SearchParams = Promise<{ desde?: string; hasta?: string }>;

// searchParams se lee dentro de <Suspense> para que el resto de la página
// se prerenderice como shell estático (cacheComponents).
async function FilteredDashboardContent({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  const desde = sanitizeDate(params.desde);
  const hasta = sanitizeDate(params.hasta);

  return (
    <>
      <DateRangeFilter basePath="/" desde={desde} hasta={hasta} />

      <Suspense key={`${desde ?? ""}_${hasta ?? ""}`} fallback={<DashboardSkeleton />}>
        <DashboardContent desde={desde} hasta={hasta} />
      </Suspense>
    </>
  );
}

export default function DashboardPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <div className="min-h-screen bg-zinc-50 font-sans dark:bg-black">
      <div className="h-1 w-full bg-gradient-to-r from-[#FDCE00] via-[#1C8FD6] to-[#E2231A]" />
      <main className="mx-auto flex w-full max-w-4xl flex-col gap-10 px-6 py-16 sm:px-10">
        <header className="flex flex-col gap-2">
          <div className="flex items-center gap-2">
            <Image
              src="/logo-snacko.png"
              alt="Snacko"
              width={192}
              height={103}
              priority
              className="h-8 w-auto"
            />
            <p className="text-sm font-medium uppercase tracking-wide text-sky-700 dark:text-sky-400">
              Automations
            </p>
          </div>
          <h1 className="text-3xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50">
            Panel de control de calidad
          </h1>
          <p className="text-zinc-600 dark:text-zinc-400">
            Controles de sal y humedad — datos de ejemplo (sintéticos) hasta conectar las
            planillas reales.
          </p>
          <nav className="mt-4 grid gap-4 sm:grid-cols-2">
            <Link
              href="/protocolo"
              className="group flex items-center justify-between gap-4 rounded-2xl bg-[#1C8FD6] px-6 py-5 text-white shadow-sm transition hover:bg-[#1679b8] hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#1C8FD6]"
            >
              <span className="flex flex-col">
                <span className="text-lg font-semibold">Ver protocolos por lote</span>
                <span className="text-sm text-sky-100">Estadísticas y descargas por lote</span>
              </span>
              <span aria-hidden className="text-2xl transition group-hover:translate-x-1">
                →
              </span>
            </Link>
            <Link
              href="/desviaciones"
              className="group flex items-center justify-between gap-4 rounded-2xl bg-[#E2231A] px-6 py-5 text-white shadow-sm transition hover:bg-[#c01d15] hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#E2231A]"
            >
              <span className="flex flex-col">
                <span className="text-lg font-semibold">Ver desviaciones</span>
                <span className="text-sm text-red-100">Controles fuera de especificación</span>
              </span>
              <span aria-hidden className="text-2xl transition group-hover:translate-x-1">
                →
              </span>
            </Link>
          </nav>
        </header>

        <Suspense fallback={<DashboardSkeleton />}>
          <FilteredDashboardContent searchParams={searchParams} />
        </Suspense>
      </main>
    </div>
  );
}
