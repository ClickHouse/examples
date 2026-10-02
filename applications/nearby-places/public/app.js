const form = document.querySelector("#search-form");
const results = document.querySelector("#results");
const status = document.querySelector("#status");
const submit = document.querySelector("#submit");
let controller;
let sequence = 0;
const presets = {
  london: { longitude: -0.12, latitude: 51.5, radiusMeters: 1000 },
  equator: { longitude: 0, latitude: 0, radiusMeters: 1200 },
  dateline: { longitude: 179.999, latitude: 0, radiusMeters: 300 },
};
for (const button of document.querySelectorAll("[data-preset]")) {
  button.addEventListener("click", () => {
    for (const [name, value] of Object.entries(presets[button.dataset.preset])) {
      form.elements.namedItem(name).value = String(value);
    }
    form.elements.namedItem("category").value = "";
    form.requestSubmit();
  });
}
form.addEventListener("submit", (event) => {
  event.preventDefault();
  void search();
});
async function search() {
  const current = ++sequence;
  controller?.abort();
  controller = new AbortController();
  const params = new URLSearchParams();
  for (const [key, value] of new FormData(form)) {
    if (value !== "") params.set(key, String(value));
  }
  results.replaceChildren();
  status.textContent = "Looking around your point…";
  submit.disabled = true;
  try {
    const response = await fetch(`/api/nearby?${params}`, { signal: controller.signal });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error ?? "Search unavailable");
    if (current !== sequence) return;
    status.textContent = data.places.length
      ? `${data.places.length} sample ${
        data.places.length === 1 ? "place" : "places"
      } within ${data.search.radiusMeters.toLocaleString()} meters`
      : "No sample places within this radius. Try a larger radius or another sample.";
    for (const place of data.places) {
      const item = document.createElement("li");
      const card = document.createElement("article");
      card.className = "place-card";
      const icon = document.createElement("span");
      icon.className = `place-icon ${place.category}`;
      icon.setAttribute("aria-hidden", "true");
      icon.textContent = { cafe: "☕", library: "▤", park: "♧" }[place.category];
      const details = document.createElement("div");
      const category = document.createElement("p");
      category.className = "place-category";
      category.textContent = place.category;
      const name = document.createElement("h3");
      name.textContent = place.name;
      const coordinates = document.createElement("p");
      coordinates.className = "coordinates";
      coordinates.textContent = `${place.longitude.toFixed(3)}° longitude · ${
        place.latitude.toFixed(3)
      }° latitude`;
      details.append(category, name, coordinates);
      const distance = document.createElement("div");
      distance.className = "distance";
      const value = document.createElement("strong");
      value.textContent = place.distanceMeters < 1000
        ? `${place.distanceMeters.toFixed(1)} m`
        : `${(place.distanceMeters / 1000).toFixed(3)} km`;
      const caption = document.createElement("span");
      caption.textContent = "from your point";
      distance.append(value, caption);
      card.append(icon, details, distance);
      item.append(card);
      results.append(item);
    }
  } catch (error) {
    if (current !== sequence || error.name === "AbortError") return;
    status.textContent = error.message;
  } finally {
    if (current === sequence) submit.disabled = false;
  }
}
void search();
