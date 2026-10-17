import ExcelJS from "exceljs";
import { NextResponse } from "next/server";
import { getLotData, type ParameterStat } from "@/lib/protocolo";

const HEADER_FILL: ExcelJS.FillPattern = {
  type: "pattern",
  pattern: "solid",
  fgColor: { argb: "FFEFEFEA" },
};

const TITLE_FONT: Partial<ExcelJS.Font> = { bold: true, size: 14 };
const SECTION_FONT: Partial<ExcelJS.Font> = { bold: true, size: 11 };
const HEADER_FONT: Partial<ExcelJS.Font> = { bold: true, size: 10, color: { argb: "FF52514E" } };
const THIN_BORDER: Partial<ExcelJS.Borders> = {
  top: { style: "thin", color: { argb: "FFE1E0D9" } },
  bottom: { style: "thin", color: { argb: "FFE1E0D9" } },
  left: { style: "thin", color: { argb: "FFE1E0D9" } },
  right: { style: "thin", color: { argb: "FFE1E0D9" } },
};

const COLUMNS = [
  { header: "Parámetro", width: 34 },
  { header: "L.I.E.", width: 10 },
  { header: "Óptimo", width: 16 },
  { header: "L.S.E.", width: 10 },
  { header: "Promedio / Resultado", width: 20 },
  { header: "Desvío estándar", width: 14 },
  { header: "Mínimo", width: 10 },
  { header: "Máximo", width: 10 },
  { header: "N° controles", width: 12 },
  { header: "N° controles NC", width: 14 },
];

function round2(value: number | null) {
  return value === null || value === undefined ? null : Math.round(value * 100) / 100;
}

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ lote: string }> }
) {
  const { lote: loteParam } = await params;
  const lote = decodeURIComponent(loteParam);

  const { header, stats } = await getLotData(lote);

  if (!header) {
    return NextResponse.json({ error: `No se encontró el lote ${lote}` }, { status: 404 });
  }

  const workbook = new ExcelJS.Workbook();
  workbook.creator = "Snacko Automations";
  workbook.created = new Date();

  const sheet = workbook.addWorksheet("Protocolo", {
    views: [{ state: "frozen", ySplit: 0 }],
  });
  sheet.columns = COLUMNS.map((c) => ({ width: c.width }));

  let row = 1;

  sheet.mergeCells(row, 1, row, COLUMNS.length);
  const titleCell = sheet.getCell(row, 1);
  titleCell.value = "PROTOCOLO DE ANÁLISIS DE SEMIELABORADO Y PRODUCTO TERMINADO";
  titleCell.font = TITLE_FONT;
  row += 2;

  const infoRows: [string, string][] = [
    ["Producto", header.product_name ?? "Sin asignar"],
    ["Lote", header.lot_reference],
    ["Período de controles", `${header.fecha_desde} — ${header.fecha_hasta}`],
    ["Controles totales", String(header.controles)],
    ["Generado", new Date().toLocaleDateString("es-AR")],
  ];
  for (const [label, value] of infoRows) {
    sheet.getCell(row, 1).value = label;
    sheet.getCell(row, 1).font = { bold: true };
    sheet.getCell(row, 2).value = value;
    row += 1;
  }
  row += 1;

  const forms = Array.from(
    new Map(
      stats.map((r) => [
        r.control_form_id,
        { control_form_id: r.control_form_id, rfp_code: r.rfp_code, form_name: r.form_name },
      ])
    ).values()
  );

  for (const form of forms) {
    sheet.mergeCells(row, 1, row, COLUMNS.length);
    const sectionCell = sheet.getCell(row, 1);
    sectionCell.value = `${form.form_name} (${form.rfp_code})`;
    sectionCell.font = SECTION_FONT;
    sectionCell.fill = HEADER_FILL;
    row += 1;

    const headerRowIndex = row;
    COLUMNS.forEach((col, i) => {
      const cell = sheet.getCell(headerRowIndex, i + 1);
      cell.value = col.header;
      cell.font = HEADER_FONT;
      cell.fill = HEADER_FILL;
      cell.border = THIN_BORDER;
    });
    row += 1;

    for (const r of stats.filter((x) => x.control_form_id === form.control_form_id)) {
      writeDataRow(sheet, row, r);
      row += 1;
    }
    row += 1;
  }

  const buffer = await workbook.xlsx.writeBuffer();
  const filename = `Protocolo_${header.lot_reference.replace(/\s+/g, "_")}.xlsx`;

  return new NextResponse(buffer, {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}

function writeDataRow(sheet: ExcelJS.Worksheet, rowIndex: number, r: ParameterStat) {
  const label = r.unit ? `${r.label} (${r.unit})` : r.label;

  if (r.data_type === "numeric") {
    const values = [
      label,
      r.lie,
      r.optimo,
      r.lse,
      round2(r.promedio),
      round2(r.desvio),
      round2(r.minimo),
      round2(r.maximo),
      r.n,
      r.n_no_conforme,
    ];
    values.forEach((v, i) => {
      const cell = sheet.getCell(rowIndex, i + 1);
      cell.value = v ?? null;
      cell.border = THIN_BORDER;
      if (i === 9 && r.n_no_conforme > 0) {
        cell.font = { color: { argb: "FFD03B3B" }, bold: true };
      }
    });
    return;
  }

  // categórico: L.I.E./L.S.E. vacíos, Óptimo lleva el texto esperado, Promedio/Resultado
  // lleva el resultado (Conforme / NO CONFORME (n))
  const ok = r.n_texto > 0 && r.n_conforme === r.n_texto;
  const resultText =
    r.n_texto === 0
      ? "Sin datos"
      : ok
        ? "Conforme"
        : `NO CONFORME (${r.n_texto - r.n_conforme})`;

  const values: (string | number | null)[] = [
    label,
    null,
    r.expected_text,
    null,
    resultText,
    null,
    null,
    null,
    r.n_texto,
    r.n_texto - r.n_conforme,
  ];
  values.forEach((v, i) => {
    const cell = sheet.getCell(rowIndex, i + 1);
    cell.value = v;
    cell.border = THIN_BORDER;
    if (i === 4 && !ok && r.n_texto > 0) {
      cell.font = { color: { argb: "FFD03B3B" }, bold: true };
    }
  });
}
