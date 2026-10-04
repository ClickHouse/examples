import { Component, computed, signal } from '@angular/core'
import { HttpClient, HttpErrorResponse } from '@angular/common/http'
import { FormsModule } from '@angular/forms'
import { ButtonModule } from 'primeng/button'
import { SelectModule } from 'primeng/select'
import { DialogModule } from 'primeng/dialog'
import { MessageModule } from 'primeng/message'
import { TagModule } from 'primeng/tag'
import { AgGridAngular } from 'ag-grid-angular'
import { AllCommunityModule, ModuleRegistry, themeQuartz, type ColDef, type GridApi, type GridReadyEvent } from 'ag-grid-community'
import type { CountRow, CountSheet, SheetSummary } from './dto'
ModuleRegistry.registerModules([AllCommunityModule])

@Component({
  selector: 'app-root', standalone: true,
  imports: [FormsModule, ButtonModule, SelectModule, DialogModule, MessageModule, TagModule, AgGridAngular],
  templateUrl: './app.html',
})
export class AppComponent {
  readonly sheets = signal<SheetSummary[]>([])
  readonly sheet = signal<CountSheet | null>(null)
  readonly rows = signal<CountRow[]>([])
  readonly dirty = signal(false)
  readonly busy = signal(true)
  readonly conflict = signal(false)
  readonly message = signal('')
  readonly error = signal(false)
  readonly counted = computed(() => this.rows().filter((r) => r.counted !== null).length)
  readonly discrepancies = computed(() => this.rows().filter((r) => r.counted !== null && r.counted !== r.expected).length)
  readonly difference = computed(() => this.rows().reduce((sum, r) => sum + (r.counted === null ? 0 : r.counted - r.expected), 0))
  selectedId = 1
  filter = ''
  confirmFinalize = false
  confirmReload = false
  private grid?: GridApi<CountRow>
  readonly theme = themeQuartz.withParams({
    accentColor: '#c55a36', backgroundColor: '#ffffff', headerBackgroundColor: '#f6f5f1',
    foregroundColor: '#283b46', borderColor: '#e1e5e5', fontFamily: 'inherit',
    fontSize: 14, rowHeight: 58, headerHeight: 44,
  })
  readonly defaultColDef: ColDef<CountRow> = { sortable: true, filter: true, resizable: true, flex: 1, minWidth: 110 }
  readonly columns: ColDef<CountRow>[] = [
    { field: 'sku', headerName: 'Asset code', minWidth: 150, flex: 0.8 },
    { field: 'name', headerName: 'Equipment', minWidth: 220, flex: 1.8 },
    { field: 'category', minWidth: 125 },
    { field: 'expected', headerName: 'Expected', minWidth: 105, flex: 0.7 },
    {
      field: 'counted', headerName: 'Counted · edit', minWidth: 145,
      editable: () => this.sheet()?.status === 'draft' && !this.busy() && !this.conflict(),
      cellEditor: 'agTextCellEditor',
      cellClass: (p) => p.data?.counted === null ? 'unentered' : 'counted-cell',
      valueFormatter: (p) => p.value === null ? '—' : String(p.value),
      valueSetter: (p) => {
        const value = String(p.newValue ?? '').trim()
        if (value !== '' && (!/^\d+$/.test(value) || Number(value) > 1000000)) {
          this.notify('Enter a whole count from 0 to 1,000,000, or leave the cell empty.', true)
          return false
        }
        const next = value === '' ? null : Number(value)
        if (p.data.counted === next) return false
        p.data.counted = next
        return true
      },
    },
    {
      headerName: 'Difference', colId: 'difference', minWidth: 115, flex: 0.8,
      valueGetter: (p) => p.data?.counted === null || !p.data ? null : p.data.counted - p.data.expected,
      valueFormatter: (p) => p.value === null ? 'Not counted' : p.value > 0 ? '+' + p.value : String(p.value),
      cellClass: (p) => p.value ? 'discrepancy-cell' : '',
    },
  ]

  constructor(private http: HttpClient) {
    this.http.get<SheetSummary[]>('/api/stocktakes').subscribe({
      next: (sheets) => { this.sheets.set(sheets); if (sheets.length) { this.selectedId = sheets[0].id; this.load() } else this.busy.set(false) },
      error: () => { this.busy.set(false); this.notify('The count sheets could not be loaded. Check that the API is running.', true) },
    })
  }
  ready(event: GridReadyEvent<CountRow>) { this.grid = event.api }
  edited() {
    this.rows.set(this.rows().map((row) => ({ ...row })))
    this.dirty.set(true)
    this.message.set('')
  }
  private notify(text: string, error = false) { this.message.set(text); this.error.set(error) }
  private apply(sheet: CountSheet) {
    this.sheet.set(sheet)
    this.rows.set(sheet.rows.map((row) => ({ ...row })))
    this.dirty.set(false)
    this.conflict.set(false)
    this.sheets.update((sheets) => sheets.map((s) => s.id === sheet.id ? { ...s, status: sheet.status, revision: sheet.revision } : s))
  }
  load() {
    this.busy.set(true)
    this.sheet.set(null)
    this.rows.set([])
    this.http.get<CountSheet>('/api/stocktakes/' + this.selectedId).subscribe({
      next: (sheet) => { this.apply(sheet); this.busy.set(false); this.message.set('') },
      error: () => { this.busy.set(false); this.notify('The sheet could not be loaded.', true) },
    })
  }
  requestReload() {
    this.grid?.stopEditing()
    if (this.dirty()) this.confirmReload = true
    else this.load()
  }
  private failed(err: HttpErrorResponse) {
    this.busy.set(false)
    this.conflict.set(err.status === 409)
    this.grid?.refreshCells({ force: true })
    this.notify(err.error?.error?.message ?? 'The change could not be saved. Try again.', true)
  }
  save() {
    this.grid?.stopEditing()
    const sheet = this.sheet()
    if (!sheet || !this.dirty() || this.busy() || this.conflict()) return
    this.busy.set(true)
    this.http.put<CountSheet>('/api/stocktakes/' + sheet.id, {
      revision: sheet.revision,
      counts: this.rows().map((r) => ({ itemId: r.itemId, counted: r.counted })),
    }, { headers: { 'X-Asset-Audit': '1' } }).subscribe({
      next: (updated) => { this.apply(updated); this.busy.set(false); this.notify('Draft saved. Your counts are stored in Postgres.') },
      error: (err) => this.failed(err),
    })
  }
  finalize() {
    const sheet = this.sheet()
    this.confirmFinalize = false
    if (!sheet || this.dirty() || this.busy() || this.counted() !== this.rows().length) return
    this.busy.set(true)
    this.http.post<CountSheet>('/api/stocktakes/' + sheet.id + '/finalize',
      { revision: sheet.revision }, { headers: { 'X-Asset-Audit': '1' } }).subscribe({
      next: (updated) => { this.apply(updated); this.busy.set(false); this.grid?.refreshCells({ force: true }); this.notify('Count sheet finalized. These counts are now read-only.') },
      error: (err) => this.failed(err),
    })
  }
}
