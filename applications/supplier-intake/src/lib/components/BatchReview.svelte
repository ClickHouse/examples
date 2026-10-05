<script lang="ts">
  import { superForm } from 'sveltekit-superforms';
  import { zod4Client } from 'sveltekit-superforms/adapters';
  import { enhance as kitEnhance } from '$app/forms';
  import { Accordion } from 'bits-ui';
  import { mappingSchema } from '$lib/mapping';
  import { Button } from '$lib/components/ui/button';
  import { Badge } from '$lib/components/ui/badge';
  import { Input } from '$lib/components/ui/input';
  import * as Tabs from '$lib/components/ui/tabs';
  import { untrack } from 'svelte';
  import type { PageProps } from '../../routes/batches/[id]/$types';
  let { data, form: actionData }: Pick<PageProps, 'data' | 'form'> = $props();
  const { form, errors, message, enhance, submitting } = superForm(
    untrack(() => data.form),
    { validators: zod4Client(mappingSchema), resetForm: false },
  );
  const money = (cents: number) =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(
      cents / 100,
    );
</script>

<svelte:head><title>{data.batch.filename} | Supplier review</title></svelte:head>
<a href="/" class="muted underline">← Receiving desk</a>
<header class="masthead">
  <div>
    <div class="eyebrow">02 / REVIEW THE SUPPLIER SHEET</div>
    <h1>{data.batch.filename}</h1>
    <p>
      {data.batch.format.toUpperCase()} · {data.batch.row_count} source rows · Revision {data
        .batch.revision}
    </p>
  </div>
  <Badge>{data.batch.status}</Badge>
</header>
<div class="layout">
  <section class="panel">
    <h2>Match the columns</h2>
    <p class="muted">
      The source values stay unchanged. These choices define how we validate the staged
      rows.
    </p>
    <form method="POST" action="?/review" use:enhance>
      <input type="hidden" name="batchId" bind:value={$form.batchId} /><input
        type="hidden"
        name="revision"
        bind:value={$form.revision}
      />
      <fieldset disabled={$submitting || data.batch.status === 'promoted'}>
        <label for="supplier">Supplier name</label><Input
          id="supplier"
          name="supplier"
          bind:value={$form.supplier}
          maxlength={80}
          aria-invalid={Boolean($errors.supplier)}
        />{#if $errors.supplier}<p class="error">{$errors.supplier.join(' ')}</p>{/if}
        <div class="mapping-grid mt-5">
          <div>
            <label for="sku">SKU column</label><select
              id="sku"
              name="sku"
              bind:value={$form.sku}
              >{#each data.batch.headers as header}<option>{header}</option
                >{/each}</select
            >
          </div>
          <div>
            <label for="product">Product column</label><select
              id="product"
              name="product"
              bind:value={$form.product}
              >{#each data.batch.headers as header}<option>{header}</option
                >{/each}</select
            >
          </div>
          <div>
            <label for="price">USD price column</label><select
              id="price"
              name="price"
              bind:value={$form.price}
              >{#each data.batch.headers as header}<option>{header}</option
                >{/each}</select
            >
          </div>
          <div>
            <label for="stock">Stock column</label><select
              id="stock"
              name="stock"
              bind:value={$form.stock}
              >{#each data.batch.headers as header}<option>{header}</option
                >{/each}</select
            >
          </div>
        </div>
        <Button
          type="submit"
          class="mt-5"
          disabled={$submitting || data.batch.status === 'promoted'}
          >{$submitting ? 'Reviewing…' : 'Validate review'}</Button
        >
      </fieldset>
    </form>
    {#if $message}<div class="message" role="status">{$message}</div>{/if}
  </section>
  <section class="panel">
    <div class="step">03 / Promote together</div>
    <h2>One batch. One decision.</h2>
    <p class="muted">
      The entire batch must pass review. Promotion inserts every product in one
      transaction; a conflicting supplier SKU leaves all its rows in staging.
    </p>
    <div class="summary">
      <span class="pill"
        >{data.batch.row_count - data.batch.invalid_count} / {data.batch.row_count}
        {data.batch.status === 'uploaded' ? 'unreviewed' : 'valid rows'}</span
      ><span class="pill">{data.batch.invalid_count} errors</span>
    </div>
    <form method="POST" action="?/promote" use:kitEnhance>
      <input type="hidden" name="revision" value={data.batch.revision} /><Button
        type="submit"
        disabled={data.batch.status === 'uploaded' || data.batch.invalid_count > 0}
        >{data.batch.status === 'promoted'
          ? 'Check imported batch'
          : 'Promote batch'}</Button
      >
    </form>
    {#if actionData && 'promotion' in actionData}<div class="message" role="status">
        {actionData.promotion}
      </div>{/if}
    {#if data.batch.status === 'promoted'}<p class="muted mt-5">
        This batch is in the catalog. Replaying promotion does not add another copy.
      </p>{/if}
  </section>
</div>
<section class="panel">
  <Tabs.Root value="mapped"
    ><Tabs.List
      ><Tabs.Trigger value="mapped">Reviewed rows</Tabs.Trigger><Tabs.Trigger value="raw"
        >Source values</Tabs.Trigger
      ></Tabs.List
    >
    <Tabs.Content value="mapped"
      ><div class="scroll">
        <table class="catalog-table">
          <thead
            ><tr
              ><th>Source row</th><th>SKU / product</th><th>USD price</th><th>Stock</th
              ><th>Review</th></tr
            ></thead
          ><tbody
            >{#each data.rows as row}<tr class:row-error={row.errors.length > 0}
                ><td>{row.row}</td><td
                  >{row.mapped?.sku ?? '—'}
                  <div class="muted">
                    {row.mapped?.product ?? 'Awaiting valid review'}
                  </div></td
                ><td>{row.mapped ? money(row.mapped.cents) : '—'}</td><td
                  >{row.mapped?.stock ?? '—'}</td
                ><td
                  >{row.errors.length
                    ? `${row.errors.length} issues`
                    : data.batch.status === 'uploaded'
                      ? 'Not reviewed'
                      : 'Valid'}</td
                ></tr
              >{/each}</tbody
          >
        </table>
      </div></Tabs.Content
    >
    <Tabs.Content value="raw"
      ><div class="scroll">
        <table class="catalog-table">
          <thead
            ><tr
              ><th>Row</th>{#each data.batch.headers as header}<th>{header}</th
                >{/each}</tr
            ></thead
          ><tbody
            >{#each data.rows as row}<tr
                ><td>{row.row}</td>{#each data.batch.headers as header}<td
                    >{row.raw[header]}</td
                  >{/each}</tr
              >{/each}</tbody
          >
        </table>
      </div></Tabs.Content
    ></Tabs.Root
  >
  <Accordion.Root type="single"
    ><Accordion.Item value="issues"
      ><Accordion.Header
        ><Accordion.Trigger class="accordion-trigger"
          >Row corrections ({data.batch.invalid_count})</Accordion.Trigger
        ></Accordion.Header
      ><Accordion.Content
        >{#if data.batch.invalid_count}<p class="muted">
            Correct these values in the supplier spreadsheet and upload the changed file,
            or fix the column mapping above.
          </p>
          {#each data.rows.filter((row) => row.errors.length) as row}<p class="error">
              <strong>Row {row.row}:</strong>
              {row.errors.join(' ')}
            </p>{/each}{:else}<p class="muted">
            {data.batch.status === 'uploaded'
              ? 'Validate the mapping to inspect row corrections.'
              : 'No row corrections needed.'}
          </p>{/if}</Accordion.Content
      ></Accordion.Item
    ></Accordion.Root
  >
</section>
