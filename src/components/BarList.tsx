type BarRow = {
  label: string;
  value: number;
  badgeText: string;
  badgeTone: "good" | "warning" | "critical";
};

const badgeToneClasses: Record<BarRow["badgeTone"], string> = {
  good: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400",
  warning: "bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400",
  critical: "bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400",
};

export function BarList({ rows }: { rows: BarRow[] }) {
  const max = Math.max(...rows.map((r) => r.value), 1);

  return (
    <div className="flex flex-col gap-3">
      {rows.map((row) => (
        <div key={row.label} className="flex items-center gap-3">
          <span className="w-24 shrink-0 text-sm text-zinc-600 dark:text-zinc-400">
            {row.label}
          </span>
          <div className="relative flex-1">
            <div
              className="h-5 rounded-r-[4px] bg-[#2a78d6] dark:bg-[#3987e5]"
              style={{ width: `${Math.max((row.value / max) * 100, 4)}%` }}
            />
          </div>
          <span className="w-10 shrink-0 text-right text-sm tabular-nums text-zinc-500 dark:text-zinc-400">
            {row.value}
          </span>
          <span
            className={`w-16 shrink-0 rounded-full px-2 py-0.5 text-center text-xs font-medium tabular-nums ${badgeToneClasses[row.badgeTone]}`}
          >
            {row.badgeText}
          </span>
        </div>
      ))}
      {rows.length === 0 && (
        <p className="text-sm text-zinc-500 dark:text-zinc-400">Sin datos todavía.</p>
      )}
    </div>
  );
}
