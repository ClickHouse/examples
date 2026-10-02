<script>
  let { data, form } = $props();
</script>

<section class="intro">
  <p class="eyebrow">THE TEAM COLLECTION</p>
  <h1>Good things to read.</h1>
  <p>
    Keep useful articles together, with the context that makes them worth
    opening.
  </p>
</section>
<div class="columns">
  <section>
    <form class="filter" method="GET">
      <label
        >Search title and notes<input
          name="q"
          value={data.q}
          maxlength="100"
          placeholder="Try databases or migrations"
        /></label
      ><label
        >Tag<input name="tag" value={data.tag} placeholder="postgres" /></label
      ><button>Find links</button><a href="/">Clear</a>
    </form>
    {#if data.filterError}<p role="alert" class="error">
        {data.filterError}
      </p>{/if}
    <p class="count">
      {data.links.length} links shown · newest first · up to 100
    </p>
    {#each data.links as link}<article class="card">
        <div class="tags">
          {#each link.tags as tag}<a href="/?tag={encodeURIComponent(tag)}"
              >{tag}</a
            >{/each}
        </div>
        <h2><a href="/links/{link.id}">{link.title}</a></h2>
        <p>{link.notes}</p>
        <div class="meta">
          <span>Saved by {link.ownerName}</span><a
            href={link.url}
            target="_blank"
            rel="noopener noreferrer">Open link ↗</a
          >
        </div>
      </article>{:else}<article class="card">
        <h2>No links found</h2>
        <p>Save your first link, or try another filter.</p>
      </article>{/each}
  </section>
  <aside>
    <h2>Save something useful</h2>
    <p>Only you can edit links you save. Everyone signed in can read them.</p>
    {#if form?.message}<p role="alert" class="error">{form.message}</p>{/if}
    <form method="POST" action="?/save">
      <label
        >Title<input
          name="title"
          required
          maxlength="200"
          value={form?.values?.title ?? ""}
        /></label
      ><label
        >URL<input
          type="url"
          name="url"
          required
          maxlength="2048"
          value={form?.values?.url ?? ""}
        /></label
      ><label
        >Why it’s worth reading<textarea name="notes" maxlength="2000"
          >{form?.values?.notes ?? ""}</textarea
        ></label
      ><label
        >Tags, separated by commas<input
          name="tags"
          maxlength="300"
          placeholder="postgres, design"
          value={form?.values?.tags ?? ""}
        /></label
      ><button>Save link</button>
    </form>
  </aside>
</div>
