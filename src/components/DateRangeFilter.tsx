// Filtro de rango de fechas — formulario GET nativo (sin JS): al enviarlo, el navegador
// navega a la misma página con ?desde=...&hasta=... en la URL, y el Server Component
// vuelve a consultar Supabase ya filtrado. Funciona igual con o sin JavaScript.
export function DateRangeFilter({
  basePath,
  desde,
  hasta,
}: {
  basePath: string;
  desde: string | null;
  hasta: string | null;
}) {
  const hasFilter = Boolean(desde || hasta);

  return (
    <form
      method="get"
      className="flex flex-wrap items-end gap-3 rounded-xl border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-950"
    >
      <div className="flex flex-col gap-1">
        <label htmlFor="desde" className="text-xs font-medium text-zinc-500 dark:text-zinc-400">
          Desde
        </label>
        <input
          id="desde"
          type="date"
          name="desde"
          defaultValue={desde ?? ""}
          className="rounded-lg border border-zinc-300 bg-white px-3 py-1.5 text-sm text-zinc-900 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100"
        />
      </div>
      <div className="flex flex-col gap-1">
        <label htmlFor="hasta" className="text-xs font-medium text-zinc-500 dark:text-zinc-400">
          Hasta
        </label>
        <input
          id="hasta"
          type="date"
          name="hasta"
          defaultValue={hasta ?? ""}
          className="rounded-lg border border-zinc-300 bg-white px-3 py-1.5 text-sm text-zinc-900 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100"
        />
      </div>
      <button
        type="submit"
        className="rounded-lg bg-sky-600 px-4 py-1.5 text-sm font-medium text-white transition hover:bg-sky-700 dark:bg-sky-500 dark:hover:bg-sky-400"
      >
        Filtrar
      </button>
      {hasFilter && (
        <a
          href={basePath}
          className="text-sm font-medium text-zinc-500 underline-offset-2 hover:underline dark:text-zinc-400"
        >
          Limpiar filtro
        </a>
      )}
    </form>
  );
}
