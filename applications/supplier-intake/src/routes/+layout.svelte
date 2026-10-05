<script lang="ts">
  import '../styles.css';
  let { children } = $props();
</script>

<div class="shell">
  {@render children()}
  <footer>
    Supplier intake · SvelteKit, Superforms and Postgres · One trusted operator
  </footer>
</div>
