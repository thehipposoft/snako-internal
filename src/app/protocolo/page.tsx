import Link from "next/link";
import { Suspense } from "react";
import { supabaseServer } from "@/lib/supabase/server";

type LotSummary = {
  lot_reference: string;
  product_name: string | null;
  fecha_desde: string;
  fecha_hasta: string;
  controles: number;
};

async function getLots(): Promise<LotSummary[]> {
  const supabase = supabaseServer();
  const { data, error } = await supabase
    .from("lot_summary")
    .select("lot_reference, product_name, fecha_desde, fecha_hasta, controles")
    .order("fecha_desde", { ascending: false });

  if (error) {
    throw new Error(`No se pudo leer lot_summary: ${error.message}`);
  }

  return data ?? [];
}

async function LotList() {
  const lots = await getLots();

  return (
    <div className="flex flex-col gap-3">
      {lots.map((lot) => (
        <Link
          key={lot.lot_reference}
          href={`/protocolo/${encodeURIComponent(lot.lot_reference)}`}
          className="flex items-center justify-between rounded-xl border border-zinc-200 bg-white p-4 transition hover:border-emerald-400 dark:border-zinc-800 dark:bg-zinc-950"
        >
          <div>
            <p className="font-mono text-sm text-zinc-500 dark:text-zinc-400">
              {lot.lot_reference}
            </p>
            <p className="font-medium text-zinc-950 dark:text-zinc-50">
              {lot.product_name ?? "Producto sin asignar"}
            </p>
            <p className="text-sm text-zinc-500 dark:text-zinc-400">
              {lot.fecha_desde} — {lot.fecha_hasta} · {lot.controles} controles
            </p>
          </div>
          <span className="text-emerald-600 dark:text-emerald-400">Ver protocolo →</span>
        </Link>
      ))}
      {lots.length === 0 && (
        <p className="rounded-xl border border-dashed border-zinc-300 p-6 text-center text-zinc-500 dark:border-zinc-700">
          Todavía no hay lotes cargados.
        </p>
      )}
    </div>
  );
}

function LotListSkeleton() {
  return (
    <div className="flex flex-col gap-3">
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="h-20 animate-pulse rounded-xl bg-zinc-100 dark:bg-zinc-900" />
      ))}
    </div>
  );
}

export default function ProtocoloIndexPage() {
  return (
    <div className="min-h-screen bg-zinc-50 font-sans dark:bg-black">
      <main className="mx-auto flex w-full max-w-3xl flex-col gap-8 px-6 py-16 sm:px-10">
        <header className="flex flex-col gap-2">
          <p className="text-sm font-medium uppercase tracking-wide text-emerald-600 dark:text-emerald-400">
            Snacko Automations
          </p>
          <h1 className="text-3xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50">
            Protocolos por lote
          </h1>
          <p className="text-zinc-600 dark:text-zinc-400">
            Lotes con controles cargados. Los datos de abajo son de ejemplo (sintéticos) hasta
            conectar las planillas reales de Snacko.
          </p>
        </header>

        <Suspense fallback={<LotListSkeleton />}>
          <LotList />
        </Suspense>
      </main>
    </div>
  );
}
