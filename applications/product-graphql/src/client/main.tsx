import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  Provider,
  createClient,
  cacheExchange,
  fetchExchange,
  useQuery,
  useMutation,
} from "urql";
import {
  CatalogDocument,
  CollectionListDocument,
  CollectionDetailDocument,
  NewCollectionDocument,
  SaveCollectionDocument,
  type CatalogQuery,
} from "./gql/graphql";
import "./style.css";
type Product = CatalogQuery["products"][number];
const client = createClient({
  url: window.location.origin + "/graphql",
  exchanges: [cacheExchange, fetchExchange],
  requestPolicy: "network-only",
});
const seed = "67bc2cf0-5b0f-45c8-bf6a-7b4bb5155a50";
function Studio() {
  const [searchText, setSearchText] = useState("");
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("");
  const [offset, setOffset] = useState(0);
  const [id, setId] = useState(
    new URLSearchParams(window.location.search).get("collection") || seed,
  );
  const [catalog] = useQuery({
    query: CatalogDocument,
    variables: {
      first: 12,
      offset,
      search: search || null,
      category: category || null,
    },
  });
  const [list, reloadList] = useQuery({ query: CollectionListDocument });
  const [detail, reload] = useQuery({
    query: CollectionDetailDocument,
    variables: { id },
  });
  const [creating, create] = useMutation(NewCollectionDocument);
  const [saving, save] = useMutation(SaveCollectionDocument);
  const [draft, setDraft] = useState<Product[]>([]);
  const [loaded, setLoaded] = useState<{
    title: string;
    revision: number;
  } | null>(null);
  const [dirty, setDirty] = useState(false);
  const [message, setMessage] = useState("");
  const [conflict, setConflict] = useState(false);
  const [name, setName] = useState("New collection");
  useEffect(() => {
    if (detail.data?.collection === null) {
      setLoaded(null);
      setDraft([]);
      setDirty(false);
      setConflict(false);
    }
    if (detail.data?.collection?.id === id) {
      setDraft(detail.data.collection.products);
      setLoaded(detail.data.collection);
      setDirty(false);
      setConflict(false);
      setMessage("");
    }
  }, [detail.data, id]);
  const missing = !detail.fetching && detail.data?.collection === null;
  const busy = detail.fetching || saving.fetching || creating.fetching;
  function edit(next: Product[]) {
    setDraft(next);
    setDirty(true);
    setMessage("");
  }
  function activate(next: string) {
    const url = new URL(window.location.href);
    url.searchParams.set("collection", next);
    history.replaceState(null, "", url);
    setId(next);
  }
  function choose(next: string) {
    if (next === id) return;
    if (dirty && !confirm("Discard unsaved collection changes?")) return;
    activate(next);
    setLoaded(null);
  }
  async function persist() {
    if (!loaded) return;
    const result = await save({
      id,
      baseRevision: loaded.revision,
      productIds: draft.map((p) => p.id),
    });
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    const answer = result.data?.replaceCollection;
    if (answer?.status === "CONFLICT") {
      setConflict(true);
      setMessage(
        "Collection changed in another tab. Your draft is still here.",
      );
      return;
    }
    if (answer?.collection) {
      setLoaded(answer.collection);
      setDraft(answer.collection.products);
      setDirty(false);
      setMessage("Collection saved");
      reloadList({ requestPolicy: "network-only" });
    }
  }
  async function newCollection() {
    const result = await create({
      title: name,
      productIds: draft.map((p) => p.id),
    });
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    if (result.data) {
      activate(result.data.createCollection.id);
      setLoaded(null);
      setDirty(false);
      reloadList({ requestPolicy: "network-only" });
    }
  }
  return (
    <>
      <header>
        <a className="brand" href="/">
          ▦{" "}
          <span>
            Collection studio<small>Make room for good things.</small>
          </span>
        </a>
        <span className="badge">Trusted local demo</span>
      </header>
      <main>
        <section className="intro">
          <div>
            <p className="eyebrow">THE CURATOR’S DESK</p>
            <h1>A considered collection.</h1>
            <p>Explore the catalogue. Choose the pieces. Save the order.</p>
          </div>
          <div className="stat">
            <small>CATALOGUE</small>
            <strong>24</strong>
            <span>objects · 3 variants each</span>
          </div>
        </section>
        <div className="layout">
          <section className="catalog">
            <form
              className="filters"
              onSubmit={(e) => {
                e.preventDefault();
                setSearch(searchText);
                setOffset(0);
              }}
            >
              <input
                aria-label="Search products"
                placeholder="Find an object…"
                maxLength={60}
                value={searchText}
                onChange={(e) => setSearchText(e.target.value)}
              />
              <select
                aria-label="Category"
                value={category}
                onChange={(e) => {
                  setCategory(e.target.value);
                  setOffset(0);
                }}
              >
                <option value="">All categories</option>
                {["Desk", "Travel", "Lighting"].map((v) => (
                  <option key={v}>{v}</option>
                ))}
              </select>
              <button>Search</button>
            </form>
            {catalog.error && <p role="alert">{catalog.error.message}</p>}
            <div className="cards" aria-busy={catalog.fetching}>
              {catalog.data?.products.map((product) => (
                <article
                  className="card"
                  key={product.id}
                  data-testid="product"
                >
                  <div
                    className={"illustration " + product.category.toLowerCase()}
                  >
                    <span>
                      {product.category === "Desk"
                        ? "▱"
                        : product.category === "Travel"
                          ? "◈"
                          : "◉"}
                    </span>
                    <small>{product.category}</small>
                  </div>
                  <div className="card-body">
                    <h2>{product.name}</h2>
                    <p>{product.description}</p>
                    <details>
                      <summary>
                        {product.variants.length} variants · from $
                        {(
                          Math.min(
                            ...product.variants.map((v) => v.priceCents),
                          ) / 100
                        ).toFixed(2)}
                      </summary>
                      <ul>
                        {product.variants.map((v) => (
                          <li key={v.id}>
                            <b>{v.name}</b>
                            <span>${(v.priceCents / 100).toFixed(2)}</span>
                            <small>{v.sku}</small>
                          </li>
                        ))}
                      </ul>
                    </details>
                    <button
                      disabled={
                        busy ||
                        draft.some((p) => p.id === product.id) ||
                        draft.length >= 12
                      }
                      onClick={() => edit([...draft, product])}
                    >
                      {draft.some((p) => p.id === product.id)
                        ? "In collection"
                        : "Add " + product.name}
                    </button>
                  </div>
                </article>
              ))}
            </div>
            <nav>
              <button
                disabled={offset === 0 || catalog.fetching}
                onClick={() => setOffset(offset - 12)}
              >
                Previous
              </button>
              <span>
                {(catalog.data?.products.length ?? 0) === 0
                  ? "No matching products"
                  : `Showing ${offset + 1}–${offset + (catalog.data?.products.length ?? 0)}`}
              </span>
              <button
                disabled={
                  (catalog.data?.products.length ?? 0) < 12 || catalog.fetching
                }
                onClick={() => setOffset(offset + 12)}
              >
                Next
              </button>
            </nav>
          </section>
          <aside>
            <p className="eyebrow">YOUR EDIT</p>
            <select
              aria-label="Saved collection"
              disabled={busy}
              value={id}
              onChange={(e) => choose(e.target.value)}
            >
              {!list.data?.collections.some((c) => c.id === id) && (
                <option value={id}>
                  {loaded?.title ||
                    (missing ? "Collection not found" : "Loading collection…")}
                </option>
              )}
              {list.data?.collections.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.title}
                </option>
              ))}
            </select>
            <div className="collection-heading">
              <h2>
                {loaded?.title ||
                  (missing ? "Collection not found" : "Loading collection…")}
              </h2>
              <span data-testid="revision">
                {loaded ? "r" + loaded.revision : "—"}
              </span>
            </div>
            <p className="subtle">
              Up to 12 products. The order is part of the collection.
            </p>
            <ol className="selection">
              {draft.map((p, i) => (
                <li key={p.id}>
                  <span className="number">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <strong>{p.name}</strong>
                    <small>
                      {p.category} · {p.variants.length} variants
                    </small>
                  </div>
                  <div className="item-actions">
                    <button
                      aria-label={"Move " + p.name + " up"}
                      disabled={busy || i === 0}
                      onClick={() => {
                        const next = [...draft];
                        [next[i - 1], next[i]] = [next[i], next[i - 1]];
                        edit(next);
                      }}
                    >
                      ↑
                    </button>
                    <button
                      aria-label={"Remove " + p.name}
                      disabled={busy}
                      onClick={() => edit(draft.filter((q) => q.id !== p.id))}
                    >
                      ×
                    </button>
                  </div>
                </li>
              ))}
            </ol>
            {!draft.length && (
              <p className="empty">Start with something you love.</p>
            )}
            <p className="status" role="status">
              {message || (dirty ? "Unsaved changes" : "Saved in Postgres")}
            </p>
            <button
              className="primary"
              disabled={busy || !dirty || conflict || !loaded}
              onClick={persist}
            >
              Save collection
            </button>
            <button
              className="reload"
              disabled={busy}
              onClick={() => {
                if (!dirty || confirm("Discard unsaved changes and reload?"))
                  reload({ requestPolicy: "network-only" });
              }}
            >
              {conflict ? "Reload saved collection" : "Reload collection"}
            </button>
            <div className="new-collection">
              <label htmlFor="title">Save this edit as a new collection</label>
              <input
                id="title"
                maxLength={60}
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
              <button disabled={busy || !name.trim()} onClick={newCollection}>
                Create collection
              </button>
            </div>
            <p className="footnote">
              Two tabs can edit the same collection. A stale save keeps your
              draft and asks you to reload.
            </p>
            {detail.error && <p role="alert">{detail.error.message}</p>}
          </aside>
        </div>
        <footer>
          Yoga · Pothos · Drizzle · Code Generator · urql{" "}
          <span>ClickHouse Managed Postgres</span>
        </footer>
      </main>
    </>
  );
}
createRoot(document.getElementById("root")!).render(
  <Provider value={client}>
    <Studio />
  </Provider>,
);
