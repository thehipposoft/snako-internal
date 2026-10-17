import { Document, Page, View, Text, StyleSheet, renderToBuffer } from "@react-pdf/renderer";
import { NextResponse } from "next/server";
import { getLotData, type ParameterStat } from "@/lib/protocolo";

const COLORS = {
  ink: "#0b0b0b",
  secondary: "#52514e",
  muted: "#898781",
  border: "#e1e0d9",
  headerFill: "#f4f3f0",
  critical: "#d03b3b",
  good: "#0ca30c",
};

const styles = StyleSheet.create({
  page: { padding: 28, fontSize: 9, fontFamily: "Helvetica", color: COLORS.ink },
  title: { fontSize: 15, fontFamily: "Helvetica-Bold", marginBottom: 10 },
  infoRow: { flexDirection: "row", marginBottom: 2 },
  infoLabel: { width: 110, fontFamily: "Helvetica-Bold", color: COLORS.secondary },
  infoValue: { color: COLORS.ink },
  sectionHeader: {
    backgroundColor: COLORS.headerFill,
    paddingVertical: 4,
    paddingHorizontal: 6,
    marginTop: 14,
    marginBottom: 4,
    fontFamily: "Helvetica-Bold",
    fontSize: 10,
  },
  tableHeaderRow: {
    flexDirection: "row",
    backgroundColor: COLORS.headerFill,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
    paddingVertical: 3,
  },
  tableRow: {
    flexDirection: "row",
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
    paddingVertical: 3,
  },
  headerCell: { fontFamily: "Helvetica-Bold", color: COLORS.secondary, fontSize: 7.5 },
  cell: { color: COLORS.ink },
  footer: {
    position: "absolute",
    bottom: 18,
    left: 28,
    right: 28,
    fontSize: 7,
    color: COLORS.muted,
  },
});

// Anchos de columna como porcentajes de flexBasis.
const COL = {
  param: { flexBasis: "26%" },
  lie: { flexBasis: "8%" },
  optimo: { flexBasis: "14%" },
  lse: { flexBasis: "8%" },
  promedio: { flexBasis: "14%" },
  desvio: { flexBasis: "10%" },
  min: { flexBasis: "7%" },
  max: { flexBasis: "7%" },
  n: { flexBasis: "8%" },
  nc: { flexBasis: "8%" },
};

function round2(value: number | null) {
  return value === null || value === undefined ? "—" : value.toFixed(2);
}

function ProtocoloDocument({
  header,
  forms,
  stats,
}: {
  header: NonNullable<Awaited<ReturnType<typeof getLotData>>["header"]>;
  forms: { control_form_id: number; rfp_code: string; form_name: string }[];
  stats: ParameterStat[];
}) {
  return (
    <Document>
      <Page size="A4" orientation="landscape" style={styles.page}>
        <Text style={styles.title}>
          PROTOCOLO DE ANÁLISIS DE SEMIELABORADO Y PRODUCTO TERMINADO
        </Text>

        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Producto</Text>
          <Text style={styles.infoValue}>{header.product_name ?? "Sin asignar"}</Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Lote</Text>
          <Text style={styles.infoValue}>{header.lot_reference}</Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Período de controles</Text>
          <Text style={styles.infoValue}>
            {header.fecha_desde} — {header.fecha_hasta}
          </Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Controles totales</Text>
          <Text style={styles.infoValue}>{header.controles}</Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Generado</Text>
          <Text style={styles.infoValue}>{new Date().toLocaleDateString("es-AR")}</Text>
        </View>

        {forms.map((form) => {
          const rows = stats.filter((r) => r.control_form_id === form.control_form_id);
          return (
            <View key={form.rfp_code} wrap={false}>
              <Text style={styles.sectionHeader}>
                {form.form_name} ({form.rfp_code})
              </Text>
              <View style={styles.tableHeaderRow}>
                <Text style={[styles.headerCell, COL.param]}>Parámetro</Text>
                <Text style={[styles.headerCell, COL.lie]}>L.I.E.</Text>
                <Text style={[styles.headerCell, COL.optimo]}>Óptimo</Text>
                <Text style={[styles.headerCell, COL.lse]}>L.S.E.</Text>
                <Text style={[styles.headerCell, COL.promedio]}>Promedio / Resultado</Text>
                <Text style={[styles.headerCell, COL.desvio]}>Desvío</Text>
                <Text style={[styles.headerCell, COL.min]}>Mín</Text>
                <Text style={[styles.headerCell, COL.max]}>Máx</Text>
                <Text style={[styles.headerCell, COL.n]}>N°</Text>
                <Text style={[styles.headerCell, COL.nc]}>N° NC</Text>
              </View>
              {rows.map((row) => (
                <DataRow key={row.param_key} row={row} />
              ))}
            </View>
          );
        })}

        <Text
          style={styles.footer}
          render={({ pageNumber, totalPages }) => `Página ${pageNumber} de ${totalPages}`}
          fixed
        />
      </Page>
    </Document>
  );
}

function DataRow({ row }: { row: ParameterStat }) {
  const label = row.unit ? `${row.label} (${row.unit})` : row.label;

  if (row.data_type === "numeric") {
    const outOfSpec = row.n_no_conforme > 0;
    return (
      <View style={styles.tableRow}>
        <Text style={[styles.cell, COL.param]}>{label}</Text>
        <Text style={[styles.cell, COL.lie]}>{row.lie ?? "—"}</Text>
        <Text style={[styles.cell, COL.optimo]}>{row.optimo ?? "—"}</Text>
        <Text style={[styles.cell, COL.lse]}>{row.lse ?? "—"}</Text>
        <Text style={[styles.cell, COL.promedio, { fontFamily: "Helvetica-Bold" }]}>
          {round2(row.promedio)}
        </Text>
        <Text style={[styles.cell, COL.desvio]}>{round2(row.desvio)}</Text>
        <Text style={[styles.cell, COL.min]}>{round2(row.minimo)}</Text>
        <Text style={[styles.cell, COL.max]}>{round2(row.maximo)}</Text>
        <Text style={[styles.cell, COL.n]}>{row.n}</Text>
        <Text
          style={[
            styles.cell,
            COL.nc,
            outOfSpec ? { color: COLORS.critical, fontFamily: "Helvetica-Bold" } : {},
          ]}
        >
          {row.n_no_conforme}
        </Text>
      </View>
    );
  }

  const ok = row.n_texto > 0 && row.n_conforme === row.n_texto;
  const resultText =
    row.n_texto === 0 ? "Sin datos" : ok ? "Conforme" : `NO CONFORME (${row.n_texto - row.n_conforme})`;

  return (
    <View style={styles.tableRow}>
      <Text style={[styles.cell, COL.param]}>{label}</Text>
      <Text style={[styles.cell, COL.lie]}>—</Text>
      <Text style={[styles.cell, COL.optimo]}>{row.expected_text ?? "—"}</Text>
      <Text style={[styles.cell, COL.lse]}>—</Text>
      <Text
        style={[
          styles.cell,
          COL.promedio,
          { fontFamily: "Helvetica-Bold" },
          !ok && row.n_texto > 0 ? { color: COLORS.critical } : {},
        ]}
      >
        {resultText}
      </Text>
      <Text style={[styles.cell, COL.desvio]}>—</Text>
      <Text style={[styles.cell, COL.min]}>—</Text>
      <Text style={[styles.cell, COL.max]}>—</Text>
      <Text style={[styles.cell, COL.n]}>{row.n_texto}</Text>
      <Text style={[styles.cell, COL.nc]}>{row.n_texto - row.n_conforme}</Text>
    </View>
  );
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

  const forms = Array.from(
    new Map(
      stats.map((r) => [
        r.control_form_id,
        { control_form_id: r.control_form_id, rfp_code: r.rfp_code, form_name: r.form_name },
      ])
    ).values()
  );

  const buffer = await renderToBuffer(
    <ProtocoloDocument header={header} forms={forms} stats={stats} />
  );
  const filename = `Protocolo_${header.lot_reference.replace(/\s+/g, "_")}.pdf`;

  return new NextResponse(new Uint8Array(buffer), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}
