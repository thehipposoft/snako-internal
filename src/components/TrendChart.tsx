"use client";

import { useRef, useState } from "react";

type TrendPoint = {
  label: string;
  pct: number;
  n: number;
};

const WIDTH = 600;
const HEIGHT = 180;
const PAD_LEFT = 32;
const PAD_RIGHT = 12;
const PAD_TOP = 16;
const PAD_BOTTOM = 24;

export function TrendChart({ data }: { data: TrendPoint[] }) {
  const svgRef = useRef<SVGSVGElement>(null);
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);

  if (data.length === 0) {
    return <p className="text-sm text-zinc-500 dark:text-zinc-400">Sin datos todavía.</p>;
  }

  const plotWidth = WIDTH - PAD_LEFT - PAD_RIGHT;
  const plotHeight = HEIGHT - PAD_TOP - PAD_BOTTOM;

  const x = (i: number) =>
    data.length === 1 ? PAD_LEFT : PAD_LEFT + (i / (data.length - 1)) * plotWidth;
  const y = (pct: number) => PAD_TOP + (1 - pct / 100) * plotHeight;

  const linePath = data.map((d, i) => `${i === 0 ? "M" : "L"}${x(i)},${y(d.pct)}`).join(" ");
  const areaPath = `${linePath} L${x(data.length - 1)},${PAD_TOP + plotHeight} L${x(0)},${PAD_TOP + plotHeight} Z`;

  const gridTicks = [0, 25, 50, 75, 100];

  function handleMove(e: React.MouseEvent<SVGSVGElement>) {
    const rect = svgRef.current?.getBoundingClientRect();
    if (!rect) return;
    const fraction = (e.clientX - rect.left) / rect.width;
    const index = Math.round(fraction * (data.length - 1));
    setHoverIndex(Math.min(Math.max(index, 0), data.length - 1));
  }

  const hovered = hoverIndex !== null ? data[hoverIndex] : null;
  const last = data[data.length - 1];

  return (
    <div className="relative">
      <svg
        ref={svgRef}
        viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
        className="w-full"
        onMouseMove={handleMove}
        onMouseLeave={() => setHoverIndex(null)}
      >
        {gridTicks.map((tick) => (
          <g key={tick}>
            <line
              x1={PAD_LEFT}
              x2={WIDTH - PAD_RIGHT}
              y1={y(tick)}
              y2={y(tick)}
              className="stroke-zinc-200 dark:stroke-zinc-800"
              strokeWidth={1}
            />
            <text
              x={PAD_LEFT - 6}
              y={y(tick)}
              textAnchor="end"
              dominantBaseline="middle"
              className="fill-zinc-400 text-[9px] dark:fill-zinc-500"
            >
              {tick}%
            </text>
          </g>
        ))}

        <path
          d={areaPath}
          className="fill-[#2a78d6] dark:fill-[#3987e5]"
          fillOpacity={0.1}
          stroke="none"
        />
        <path
          d={linePath}
          fill="none"
          className="stroke-[#2a78d6] dark:stroke-[#3987e5]"
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
        />

        {/* endpoint marker + direct label */}
        <circle
          cx={x(data.length - 1)}
          cy={y(last.pct)}
          r={4}
          className="fill-[#2a78d6] dark:fill-[#3987e5] stroke-white dark:stroke-zinc-950"
          strokeWidth={2}
        />
        <text
          x={x(data.length - 1)}
          y={y(last.pct) - 10}
          textAnchor="end"
          className="fill-zinc-700 text-[10px] font-medium dark:fill-zinc-300"
        >
          {last.pct}%
        </text>

        {hovered && (
          <g>
            <line
              x1={x(hoverIndex!)}
              x2={x(hoverIndex!)}
              y1={PAD_TOP}
              y2={PAD_TOP + plotHeight}
              className="stroke-zinc-300 dark:stroke-zinc-700"
              strokeWidth={1}
            />
            <circle
              cx={x(hoverIndex!)}
              cy={y(hovered.pct)}
              r={4}
              className="fill-[#2a78d6] dark:fill-[#3987e5] stroke-white dark:stroke-zinc-950"
              strokeWidth={2}
            />
          </g>
        )}
      </svg>

      {hovered && hoverIndex !== null && (
        <div
          className="pointer-events-none absolute top-0 -translate-x-1/2 rounded-lg border border-zinc-200 bg-white px-2.5 py-1.5 text-xs shadow-sm dark:border-zinc-800 dark:bg-zinc-900"
          style={{ left: `${(x(hoverIndex) / WIDTH) * 100}%` }}
        >
          <p className="font-medium text-zinc-900 dark:text-zinc-100">{hovered.label}</p>
          <p className="text-zinc-500 dark:text-zinc-400">
            {hovered.pct}% cumplimiento · {hovered.n} controles
          </p>
        </div>
      )}
    </div>
  );
}
