<script setup lang="ts">
const { loggedIn } = useUserSession();
if (!loggedIn.value) await navigateTo("/login");
const route = useRoute();
const query = computed(() => ({
  q: String(route.query.q || ""),
  location: String(route.query.location || ""),
  skill: String(route.query.skill || ""),
  sort: String(route.query.sort || "name"),
  page: String(route.query.page || "1"),
}));
const { data, error, pending } = await useFetch<any>("/api/directory", {
  query,
});
const { data: skills } = await useFetch<any[]>("/api/skills");
const search = ref(query.value.q);
const location = ref(query.value.location);
const skill = ref(query.value.skill);
const sort = ref(query.value.sort);
function filter() {
  navigateTo({
    path: "/",
    query: {
      q: search.value,
      location: location.value,
      skill: skill.value,
      sort: sort.value,
      page: "1",
    },
  });
}
function page(value: number) {
  navigateTo({ path: "/", query: { ...query.value, page: String(value) } });
}
const errorMessage = computed(
  () =>
    (error.value?.data as any)?.statusMessage ||
    "The directory is temporarily unavailable.",
);
</script>
<template>
  <section>
    <div class="page-heading">
      <div>
        <p class="eyebrow">Your team, at a glance</p>
        <h1>People directory</h1>
        <p>Find a colleague by name, location, or skill.</p>
      </div>
      <NuxtLink class="primary link-button" to="/profile"
        >Edit my profile <span>↗</span></NuxtLink
      >
    </div>
    <form class="filters panel" @submit.prevent="filter">
      <label class="search"
        >Search<input
          v-model="search"
          placeholder="Name, biography, or location"
          maxlength="80"
          type="search" /></label
      ><label
        >Location<input
          v-model="location"
          placeholder="Any location"
          maxlength="80" /></label
      ><label
        >Skill<select v-model="skill" aria-label="Skill">
          <option value="">All skills</option>
          <option v-for="s in skills" :key="s.id" :value="String(s.id)">
            {{ s.name }}
          </option>
        </select></label
      ><label
        >Sort<select v-model="sort" aria-label="Sort">
          <option value="name">Name</option>
          <option value="recent">Recently updated</option>
        </select></label
      ><button class="primary">Find people</button>
    </form>
    <p v-if="error" role="alert" class="error">{{ errorMessage }}</p>
    <template v-else-if="data"
      ><div class="results-line">
        <p>
          <strong>{{ data.total }}</strong>
          {{ data.total === 1 ? "colleague" : "colleagues"
          }}<span v-if="pending"> · Updating…</span>
        </p>
        <span>Page {{ data.page }} · Up to 12 people</span>
      </div>
      <div class="people-grid">
        <article
          v-for="person in data.profiles"
          :key="person.id"
          class="person-card panel"
        >
          <div class="person-top">
            <span class="avatar">{{
              person.display_name
                .split(" ")
                .map((n: string) => n[0])
                .slice(0, 2)
                .join("")
            }}</span>
            <div>
              <h2>{{ person.display_name }}</h2>
              <p>{{ person.location || "Location not set" }}</p>
            </div>
          </div>
          <p class="bio">
            {{
              person.biography ||
              "This colleague has not added a biography yet."
            }}
          </p>
          <div class="tags">
            <span v-for="s in person.skills" :key="s.id">{{ s.name }}</span
            ><span v-if="!person.skills.length" class="empty-tag"
              >No skills added</span
            >
          </div>
        </article>
      </div>
      <div v-if="!data.profiles.length" class="empty-state panel">
        <h2>No colleagues match</h2>
        <p>Try a different search or remove a filter.</p>
      </div>
      <nav class="pagination" aria-label="Directory pages">
        <button
          :disabled="data.page <= 1 || pending"
          @click="page(data.page - 1)"
        >
          ← Previous</button
        ><span
          >Page {{ data.page }} of
          {{ Math.max(1, Math.ceil(data.total / 12)) }}</span
        ><button
          :disabled="data.page * 12 >= data.total || pending"
          @click="page(data.page + 1)"
        >
          Next →
        </button>
      </nav></template
    >
  </section>
</template>
