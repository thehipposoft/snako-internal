type StatTileProps = {
  label: string;
  value: string;
  tone?: "default" | "good" | "warning" | "critical";
  helpText?: string;
};

const toneClasses: Record<NonNullable<StatTileProps["tone"]>, string> = {
  default: "text-zinc-950 dark:text-zinc-50",
  good: "text-[#0ca30c]",
  warning: "text-[#b5790f] dark:text-[#fab219]",
  critical: "text-[#d03b3b]",
};

export function StatTile({ label, value, tone = "default", helpText }: StatTileProps) {
  return (
    <div className="rounded-xl border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-950">
      <p className={`text-2xl font-semibold ${toneClasses[tone]}`}>{value}</p>
      <p className="text-sm text-zinc-500 dark:text-zinc-400">{label}</p>
      {helpText && <p className="mt-1 text-xs text-zinc-400 dark:text-zinc-500">{helpText}</p>}
    </div>
  );
}
