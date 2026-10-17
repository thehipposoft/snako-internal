import Link from "next/link";
import { Suspense } from "react";
import { notFound } from "next/navigation";
import { getLotData, type ParameterStat } from "@/lib/protocolo";

function numberOrDash(value: number | null, digits = 2) {
  return value === null || value === undefined ? "—" : value.toFixed(digits);
}

function complianceBadge(row: ParameterStat) {
  if (row.data_type === "text") {
    if (row.n_texto === 0) return null;
    const ok = row.n_conforme === row.n_texto;
    return (
      <span
        className={`rounded-full px-2 py-0.5 text-xs font-medium ${
          ok
            ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400"
            : "bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400"
        }`}
      >
        {row.n_conforme}/{row.n_texto} conforme
      </span>
    );
  }

  if (row.promedio === null || (row.lie === null && row.lse === null)) return null;

  const ok = (row.lie === null || row.promedio >= row.lie) && (row.lse === null || row.promedio <= row.lse);

  return (
    <span
      className={`rounded-full px-2 py-0.5 text-xs font-medium ${
        ok
          ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400"
          : "bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400"
      }`}
    >
      {ok ? "Cumple" : "Fuera de especificación"}
    </span>
  );
}

async function LoteContent({ lote }: { lote: string }) {
  const { header, stats } = await getLotData(lote);

  if (!header) notFound();

  const forms = Array.from(
    new Map(stats.map((row) => [row.control_form_id, { rfp_code: row.rfp_code, form_name: row.form_name }])).values()
  );

  return (
    <>
      <header className="flex flex-col gap-1">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-sm font-medium uppercase tracking-wide text-emerald-600 dark:text-emerald-400">
              Protocolo de calidad
            </p>
            <h1 className="text-3xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50">
              Lote {header.lot_reference}
            </h1>
          </div>
          <div className="flex items-center gap-2">
            <a
              href={`/protocolo/${encodeURIComponent(header.lot_reference)}/excel`}
              className="inline-flex items-center gap-2 rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm font-medium text-zinc-700 transition hover:border-emerald-400 hover:text-emerald-700 dark:border-zinc-800 dark:bg-zinc-950 dark:text-zinc-300 dark:hover:text-emerald-400"
            >
              Descargar Excel
            </a>
            <a
              href={`/protocolo/${encodeURIComponent(header.lot_reference)}/pdf`}
              className="inline-flex items-center gap-2 rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm font-medium text-zinc-700 transition hover:border-emerald-400 hover:text-emerald-700 dark:border-zinc-800 dark:bg-zinc-950 dark:text-zinc-300 dark:hover:text-emerald-400"
            >
              Descargar PDF
            </a>
          </div>
        </div>
        <p className="text-zinc-600 dark:text-zinc-400">
          {header.product_name ?? "Producto sin asignar"} · {header.fecha_desde} —{" "}
          {header.fecha_hasta} · {header.controles} controles
        </p>
      </header>

      {forms.map((form) => {
        const rows = stats.filter((r) => r.rfp_code === form.rfp_code);
        return (
          <section key={form.rfp_code} className="flex flex-col gap-3">
            <h2 className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
              {form.form_name}{" "}
              <span className="font-mono text-sm font-normal text-zinc-500">
                ({form.rfp_code})
              </span>
            </h2>
            <div className="overflow-x-auto rounded-xl border border-zinc-200 dark:border-zinc-800">
              <table className="w-full min-w-[640px] text-left text-sm">
                <thead className="bg-zinc-100 text-zinc-600 dark:bg-zinc-900 dark:text-zinc-400">
                  <tr>
                    <th className="px-4 py-3 font-medium">Parámetro</th>
                    <th className="px-4 py-3 font-medium">N</th>
                    <th className="px-4 py-3 font-medium">Promedio</th>
                    <th className="px-4 py-3 font-medium">Desvío</th>
                    <th className="px-4 py-3 font-medium">Mín</th>
                    <th className="px-4 py-3 font-medium">Máx</th>
                    <th className="px-4 py-3 font-medium">L.I.E. / Óptimo / L.S.E.</th>
                    <th className="px-4 py-3 font-medium">Estado</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
                  {rows.map((row) => (
                    <tr key={row.param_key}>
                      <td className="px-4 py-3 text-zinc-800 dark:text-zinc-200">
                        {row.label}
                        {row.unit ? ` (${row.unit})` : ""}
                      </td>
                      {row.data_type === "numeric" ? (
                        <>
                          <td className="px-4 py-3 text-zinc-500">{row.n}</td>
                          <td className="px-4 py-3 font-medium text-zinc-900 dark:text-zinc-100">
                            {numberOrDash(row.promedio)}
                          </td>
                          <td className="px-4 py-3 text-zinc-500">{numberOrDash(row.desvio)}</td>
                          <td className="px-4 py-3 text-zinc-500">{numberOrDash(row.minimo)}</td>
                          <td className="px-4 py-3 text-zinc-500">{numberOrDash(row.maximo)}</td>
                          <td className="px-4 py-3 text-zinc-500">
                            {row.lie ?? "—"} / {row.optimo ?? "—"} / {row.lse ?? "—"}
                          </td>
                        </>
                      ) : (
                        <>
                          <td className="px-4 py-3 text-zinc-500">{row.n_texto}</td>
                          <td className="px-4 py-3 text-zinc-500" colSpan={4}>
                            {row.expected_text
                              ? `Esperado: "${row.expected_text}"`
                              : "Sin especificación cargada"}
                          </td>
                        </>
                      )}
                      <td className="px-4 py-3">{complianceBadge(row)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        );
      })}

      <p className="text-xs text-zinc-400">
        Promedio/Desvío/Mín/Máx calculados en SQL (vista <code>lot_parameter_stats</code>) a
        partir de los controles individuales — no hardcodeados.
      </p>
    </>
  );
}

function LoteSkeleton() {
  return (
    <div className="flex flex-col gap-8">
      <div className="h-20 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
      <div className="h-48 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
      <div className="h-48 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
    </div>
  );
}

export default async function ProtocoloLotePage({
  params,
}: {
  params: Promise<{ lote: string }>;
}) {
  const { lote } = await params;

  return (
    <div className="min-h-screen bg-zinc-50 font-sans dark:bg-black">
      <main className="mx-auto flex w-full max-w-4xl flex-col gap-8 px-6 py-16 sm:px-10">
        <Link href="/protocolo" className="text-sm text-emerald-600 dark:text-emerald-400">
          ← Todos los lotes
        </Link>
        <Suspense fallback={<LoteSkeleton />}>
          <LoteContent lote={decodeURIComponent(lote)} />
        </Suspense>
      </main>
    </div>
  );
}
