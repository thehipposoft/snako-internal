import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { supabaseServer } from "@/lib/supabase/server";
import { StatTile } from "@/components/StatTile";
import { BarList } from "@/components/BarList";
import { TrendChart } from "@/components/TrendChart";

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

async function getDashboardData() {
  const supabase = supabaseServer();

  const [overview, trend, byLine, byShift, byEmployee, resample] = await Promise.all([
    supabase.from("quality_overview").select("*").maybeSingle<Overview>(),
    supabase
      .from("quality_trend_weekly")
      .select("*")
      .order("semana")
      .returns<TrendRow[]>(),
    supabase
      .from("quality_by_line")
      .select("*")
      .order("total_controles", { ascending: false })
      .returns<GroupRow[]>(),
    supabase
      .from("quality_by_shift")
      .select("*")
      .order("total_controles", { ascending: false })
      .returns<GroupRow[]>(),
    supabase
      .from("quality_by_employee")
      .select("*")
      .order("total_controles", { ascending: false })
      .returns<GroupRow[]>(),
    supabase.from("quality_resample_rate").select("*").maybeSingle<ResampleRate>(),
  ]);

  for (const r of [overview, trend, byLine, byShift, byEmployee, resample]) {
    if (r.error) throw new Error(`No se pudo leer el dashboard: ${r.error.message}`);
  }

  return {
    overview: overview.data,
    trend: trend.data ?? [],
    byLine: byLine.data ?? [],
    byShift: byShift.data ?? [],
    byEmployee: byEmployee.data ?? [],
    resample: resample.data,
  };
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

async function DashboardContent() {
  const { overview, trend, byLine, byShift, byEmployee, resample } = await getDashboardData();

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
        Todo lo de arriba se calcula en SQL (vistas <code>quality_*</code>) a partir de los
        controles individuales — nada hardcodeado en el frontend.
      </p>
    </>
  );
}

function DashboardSkeleton() {
  return (
    <div className="flex flex-col gap-10">
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

export default function DashboardPage() {
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
            Controles de sal y humedad, últimos ~75 días — datos de ejemplo (sintéticos) hasta
            conectar las planillas reales.
          </p>
          <div className="mt-1 flex flex-wrap gap-4">
            <Link
              href="/protocolo"
              className="inline-flex w-fit items-center gap-1 text-sm font-medium text-sky-700 dark:text-sky-400"
            >
              Ver protocolos por lote →
            </Link>
            <Link
              href="/desviaciones"
              className="inline-flex w-fit items-center gap-1 text-sm font-medium text-sky-700 dark:text-sky-400"
            >
              Ver desviaciones →
            </Link>
          </div>
        </header>

        <Suspense fallback={<DashboardSkeleton />}>
          <DashboardContent />
        </Suspense>
      </main>
    </div>
  );
}
