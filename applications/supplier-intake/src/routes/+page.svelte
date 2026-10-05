<script lang="ts">
  import Uploader from '$lib/components/Uploader.svelte';
  import * as Tabs from '$lib/components/ui/tabs';
  import { Badge } from '$lib/components/ui/badge';
  import type { PageData } from './$types';
  let { data }: { data: PageData } = $props();
  const money = (cents: number) =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(
      cents / 100,
    );
</script>

<svelte:head
  ><title>Supplier intake | Receiving desk</title><meta
    name="description"
    content="Review supplier spreadsheets before promoting them to the catalog."
  /></svelte:head
>
<header class="masthead">
  <div>
    <div class="eyebrow">RECEIVING DESK / SUPPLIER INTAKE</div>
    <h1>A spreadsheet isn’t a catalog. Yet.</h1>
    <p>
      Bring in a supplier file, match its columns, and inspect the rows before anything
      reaches the catalog.
    </p>
  </div>
  <Badge variant="secondary">{data.count} catalog products</Badge>
</header>
<div class="layout">
  <section class="panel">
    <div class="step">01 / Receive a file</div>
    <h2>Start with the supplier sheet</h2>
    <p class="muted">
      Files stay in Postgres staging until you approve a valid review. Uploading the same
      bytes opens the existing batch.
    </p>
    <Uploader />
    <div class="help-links">
      <a href="/fixtures/harbor-tools.csv" download>CSV example</a><a
        href="/fixtures/meadow-textiles.xlsx"
        download>XLSX example</a
      ><a href="/fixtures/needs-correction.csv" download>Error example</a>
    </div>
  </section>
  <section class="panel">
    <div class="step">The route to the catalog</div>
    <h2>Receive → Review → Promote</h2>
    <p class="muted">
      Match SKU, product, USD price and available stock to the supplier’s headers. Review
      checks every row and keeps mistakes visible.
    </p>
    <div class="summary">
      <span class="pill">Integer cents</span><span class="pill">No partial imports</span
      ><span class="pill">Replay-safe batches</span>
    </div>
    <p class="muted">
      A duplicate supplier SKU stops the entire promotion. Correct the source spreadsheet
      and upload it again; the existing catalog remains intact.
    </p>
  </section>
</div>
<Tabs.Root value="batches"
  ><Tabs.List
    ><Tabs.Trigger value="batches">Intake batches</Tabs.Trigger><Tabs.Trigger
      value="catalog">Live catalog</Tabs.Trigger
    ></Tabs.List
  >
  <Tabs.Content value="batches"
    ><section class="panel">
      <h2>On the receiving desk</h2>
      <p class="muted">Latest 12 batches. Reopen any batch to resume its review.</p>
      <div class="scroll">
        <table>
          <thead
            ><tr><th>File</th><th>Supplier</th><th>Rows</th><th>Status</th></tr></thead
          ><tbody
            >{#each data.batches as batch}<tr
                ><td
                  ><a class="underline" href={`/batches/${batch.id}`}>{batch.filename}</a>
                  <div class="muted">
                    {batch.format.toUpperCase()} · {batch.created_at} UTC
                  </div></td
                ><td>{batch.supplier || 'Not reviewed'}</td><td>{batch.row_count}</td><td
                  ><Badge variant={batch.status === 'promoted' ? 'default' : 'secondary'}
                    >{batch.status}</Badge
                  ></td
                ></tr
              >{/each}</tbody
          >
        </table>
      </div>
    </section></Tabs.Content
  >
  <Tabs.Content value="catalog"
    ><section class="panel">
      <h2>Ready to order</h2>
      <p class="muted">
        {data.count > 200
          ? 'First 200 products, sorted by supplier and SKU.'
          : `${data.count} products in the catalog.`}
      </p>
      <div class="scroll">
        <table class="catalog-table">
          <thead
            ><tr
              ><th>Supplier / SKU</th><th>Product</th><th>USD price</th><th>Available</th
              ></tr
            ></thead
          ><tbody
            >{#each data.products as product}<tr
                ><td
                  >{product.supplier}
                  <div class="muted">{product.sku}</div></td
                ><td>{product.product}</td><td>{money(product.price_cents)}</td><td
                  >{product.stock}</td
                ></tr
              >{/each}</tbody
          >
        </table>
      </div>
    </section></Tabs.Content
  >
</Tabs.Root>
