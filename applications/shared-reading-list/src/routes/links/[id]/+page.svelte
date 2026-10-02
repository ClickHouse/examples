<script>
  let { data, form } = $props();
</script>

<a href="/" class="back">← Back to the collection</a>
<section class="detail">
  <p class="eyebrow">SAVED LINK</p>
  <h1>{data.link.title}</h1>
  <a href={data.link.url} target="_blank" rel="noopener noreferrer"
    >{data.link.url} ↗</a
  >
  <p class="notes">{data.link.notes}</p>
  <div class="tags">
    {#each data.link.tags as tag}<a href="/?tag={encodeURIComponent(tag)}"
        >{tag}</a
      >{/each}
  </div>
  <p class="meta">
    Saved {new Date(data.link.createdAt).toLocaleDateString("en-GB")} · Version {data
      .link.version}
  </p>
</section>
{#if data.isOwner}<section class="edit">
    <h2>Edit your link</h2>
    {#if form?.message}<p role="alert" class="error">{form.message}</p>{/if}
    <form method="POST" action="?/update">
      <input type="hidden" name="version" value={data.link.version} /><label
        >Title<input
          name="title"
          value={data.link.title}
          required
          maxlength="200"
        /></label
      ><label
        >URL<input
          name="url"
          type="url"
          value={data.link.url}
          required
          maxlength="2048"
        /></label
      ><label
        >Why it’s worth reading<textarea name="notes" maxlength="2000"
          >{data.link.notes}</textarea
        ></label
      ><label
        >Tags, separated by commas<input
          name="tags"
          value={data.link.tags.join(", ")}
          maxlength="300"
        /></label
      ><button>Save changes</button>
    </form>
    <form method="POST" action="?/delete" class="delete">
      <input type="hidden" name="version" value={data.link.version} /><button
        class="danger">Delete link</button
      >
    </form>
  </section>{:else}<p class="muted">
    The person who saved this link can edit or delete it.
  </p>{/if}
