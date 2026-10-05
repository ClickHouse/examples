<script lang="ts">
  import BatchReview from '$lib/components/BatchReview.svelte';
  import type { PageProps } from './$types';
  let { data, form }: PageProps = $props();
</script>

{#key data.batch.id}<BatchReview {data} {form} />{/key}
