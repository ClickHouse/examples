<script>
  import "../style.css";
  let { data, children } = $props();
</script>

<svelte:head
  ><title>Shared reading list</title><meta
    name="description"
    content="Save useful links for your team."
  /></svelte:head
>
<header>
  <a href="/" class="brand">↗ Reading room</a><span
    >A shared shelf of useful links</span
  >{#if data.user}<form method="POST" action="/sign-out">
      <button class="quiet">Sign out · {data.user.name}</button>
    </form>{/if}
</header>
<main>{@render children()}</main>
<footer>Save a link. Add some context. Find it again.</footer>
