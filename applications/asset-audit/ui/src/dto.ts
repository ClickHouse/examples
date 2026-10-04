export interface CountRow {
  itemId: number; sku: string; name: string; category: string; expected: number; counted: number | null
}
export interface SheetSummary {
  id: number; name: string; location: string; status: 'draft' | 'finalized'; revision: number
}
export interface CountSheet extends SheetSummary { finalizedAt: string | null; rows: CountRow[] }
