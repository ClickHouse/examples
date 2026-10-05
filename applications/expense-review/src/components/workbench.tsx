"use client";
import { useEffect, useRef, useState } from "react";
import {
  tableFeatures,
  useTable,
  rowSortingFeature,
  createSortedRowModel,
  sortFns,
  columnFilteringFeature,
  globalFilteringFeature,
  createFilteredRowModel,
  filterFns,
  rowSelectionFeature,
  type ColumnDef,
} from "@tanstack/react-table";
import { useVirtualizer } from "@tanstack/react-virtual";
import { client } from "@/lib/client";
import type { Summary } from "@/shared/schema";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import ClaimDialog from "./claim-dialog";
const features = tableFeatures({
  rowSortingFeature,
  sortedRowModel: createSortedRowModel(),
  sortFns,
  columnFilteringFeature,
  globalFilteringFeature,
  filteredRowModel: createFilteredRowModel(),
  filterFns,
  rowSelectionFeature,
});
export const money = (cents: number) =>
  new Intl.NumberFormat("en-GB", { style: "currency", currency: "GBP" }).format(
    cents / 100,
  );
const columns: ColumnDef<typeof features, Summary>[] = [
  {
    accessorKey: "id",
    header: "Claim",
    cell: (info) => `#${info.getValue<number>()}`,
  },
  { accessorKey: "employee", header: "Employee" },
  { accessorKey: "category", header: "Category" },
  { accessorKey: "memo", header: "Description" },
  {
    accessorKey: "status",
    header: "Status",
    cell: (info) => (
      <Badge variant={info.getValue() === "approved" ? "default" : "secondary"}>
        {info.getValue<string>()}
      </Badge>
    ),
  },
  {
    accessorKey: "totalCents",
    header: "Amount",
    cell: (info) => money(info.getValue<number>()),
    enableGlobalFilter: false,
  },
];
export default function Workbench() {
  const [claims, setClaims] = useState<Summary[]>([]),
    [total, setTotal] = useState(0),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(""),
    [selected, setSelected] = useState<number | null>(null);
  const scroll = useRef<HTMLDivElement>(null),
    request = useRef(0);
  async function reload() {
    const token = ++request.current;
    setLoading(true);
    setError("");
    try {
      const result = await client.list.query();
      if (token !== request.current) return;
      setClaims(result.claims);
      setTotal(result.totalCount);
    } catch {
      if (token === request.current)
        setError("Saved claims could not be loaded. Reload to try again.");
    } finally {
      if (token === request.current) setLoading(false);
    }
  }
  useEffect(() => {
    void reload();
    return () => {
      request.current++;
    };
  }, []);
  const table = useTable({
    key: "expense-claims",
    features,
    columns,
    data: claims,
    getRowId: (row) => String(row.id),
    enableMultiRowSelection: false,
  });
  const rows = table.getRowModel().rows;
  const virtual = useVirtualizer({
    count: rows.length,
    getScrollElement: () => scroll.current,
    estimateSize: () => 54,
    overscan: 7,
    getItemKey: (index) => rows[index]!.id,
  });
  useEffect(() => {
    virtual.scrollToOffset(0);
  }, [
    table.state.globalFilter,
    table.state.columnFilters,
    table.state.sorting,
  ]);
  const selectedRow = table.getSelectedRowModel().rows[0];
  return (
    <main className="workbench">
      <header>
        <div>
          <span className="eyebrow">FINANCE OPERATIONS</span>
          <h1>Expense review</h1>
          <p>
            Review a saved claim revision and preserve its decision history.
          </p>
        </div>
        <Badge variant="outline">GBP · synthetic claims</Badge>
      </header>
      <section className="panel">
        <div className="tools">
          <div>
            <label htmlFor="search">Search all loaded claims</label>
            <Input
              id="search"
              placeholder="Employee, category or description"
              value={table.state.globalFilter ?? ""}
              onChange={(e) => table.setGlobalFilter(e.target.value)}
            />
          </div>
          <div>
            <label htmlFor="status-filter">Status</label>
            <Select
              value={String(
                table.getColumn("status")?.getFilterValue() ?? "all",
              )}
              onValueChange={(v) =>
                table
                  .getColumn("status")
                  ?.setFilterValue(v === "all" ? undefined : v)
              }
            >
              <SelectTrigger id="status-filter">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All statuses</SelectItem>
                <SelectItem value="pending">Pending</SelectItem>
                <SelectItem value="approved">Approved</SelectItem>
                <SelectItem value="rejected">Rejected</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Button
            variant="outline"
            disabled={loading}
            onClick={() => void reload()}
          >
            Reload claims
          </Button>
        </div>
        <div className="scope">
          <p>
            {loading
              ? "Loading saved claims…"
              : `${rows.length} matching · ${claims.length} loaded · ${total} total saved claims`}
          </p>
          <p>
            {selectedRow
              ? `Selected claim #${selectedRow.original.id}`
              : "Select one claim to review"}
          </p>
        </div>
        {error && (
          <p role="alert" className="feedback error">
            {error}
          </p>
        )}
        <div
          ref={scroll}
          className="claims-scroll"
          aria-label="Expense claims"
          tabIndex={0}
        >
          <table className="claims-table" aria-rowcount={rows.length + 1}>
            <thead>
              {table.getHeaderGroups().map((group) => (
                <tr key={group.id}>
                  {group.headers.map((header) => (
                    <th key={header.id}>
                      <button
                        onClick={header.column.getToggleSortingHandler()}
                        disabled={!header.column.getCanSort()}
                      >
                        <table.FlexRender header={header} />
                        {header.column.getIsSorted() === "asc"
                          ? " ↑"
                          : header.column.getIsSorted() === "desc"
                            ? " ↓"
                            : ""}
                      </button>
                    </th>
                  ))}
                </tr>
              ))}
            </thead>
            <tbody>
              <tr
                aria-hidden="true"
                style={{ height: virtual.getVirtualItems()[0]?.start ?? 0 }}
              >
                <td colSpan={6} />
              </tr>
              {virtual.getVirtualItems().map((item) => {
                const row = rows[item.index]!;
                return (
                  <tr
                    key={row.id}
                    data-claim-id={row.original.id}
                    aria-rowindex={item.index + 2}
                    data-selected={row.getIsSelected()}
                  >
                    {row.getAllCells().map((cell, index) => (
                      <td key={cell.id}>
                        {index === 0 ? (
                          <button
                            className="claim-link"
                            disabled={loading}
                            onClick={() => {
                              row.toggleSelected(true);
                              setSelected(row.original.id);
                            }}
                          >
                            <table.FlexRender cell={cell} />
                          </button>
                        ) : (
                          <table.FlexRender cell={cell} />
                        )}
                      </td>
                    ))}
                  </tr>
                );
              })}
              <tr
                aria-hidden="true"
                style={{
                  height:
                    virtual.getTotalSize() -
                    (virtual.getVirtualItems().at(-1)?.end ?? 0),
                }}
              >
                <td colSpan={6} />
              </tr>
            </tbody>
          </table>
        </div>
        {!loading && !error && rows.length === 0 && (
          <p className="empty">No claims match these filters.</p>
        )}
        <p className="hint">
          Filters and sorting cover the complete loaded dataset. Only the
          visible table rows are mounted; scroll to review all claims.
        </p>
      </section>
      <ClaimDialog
        id={selected}
        onClose={() => setSelected(null)}
        onSaved={() => void reload()}
      />
    </main>
  );
}
