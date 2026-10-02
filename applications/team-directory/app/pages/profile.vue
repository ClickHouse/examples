<script setup lang="ts">
const { user, loggedIn } = useUserSession();
if (!loggedIn.value) await navigateTo("/login");
const {
  data: profile,
  error,
  refresh,
} = await useFetch<any>(() => `/api/profiles/${user.value?.id}`);
const { data: skills } = await useFetch<any[]>("/api/skills");
const displayName = ref("");
const biography = ref("");
const location = ref("");
const skillIds = ref<number[]>([]);
const revision = ref(0);
const message = ref("");
const isError = ref(false);
const busy = ref(false);
function loadForm() {
  if (!profile.value) return;
  displayName.value = profile.value.display_name;
  biography.value = profile.value.biography;
  location.value = profile.value.location;
  skillIds.value = profile.value.skills.map((s: any) => s.id);
  revision.value = profile.value.revision;
}
loadForm();
async function reload() {
  await refresh();
  if (error.value || !profile.value) {
    message.value =
      "The latest profile could not be loaded. Your edits are still here.";
    isError.value = true;
    return;
  }
  loadForm();
  message.value = "Latest profile loaded. Review it before saving.";
  isError.value = false;
}
async function save() {
  busy.value = true;
  message.value = "";
  try {
    const saved = await $fetch<any>(`/api/profiles/${user.value!.id}`, {
      method: "PUT",
      body: {
        revision: revision.value,
        displayName: displayName.value,
        biography: biography.value,
        location: location.value,
        skillIds: skillIds.value,
      },
    });
    profile.value = saved;
    loadForm();
    message.value = "Profile saved.";
    isError.value = false;
  } catch (e: any) {
    message.value = e.data?.statusMessage || "Saving failed. Please try again.";
    isError.value = true;
  } finally {
    busy.value = false;
  }
}
const errorMessage = computed(
  () => (error.value?.data as any)?.statusMessage || "Profile is unavailable.",
);
</script>
<template>
  <section class="profile-layout">
    <div>
      <p class="eyebrow">Make yourself easy to find</p>
      <h1>My profile</h1>
      <p>
        Your name, location, and skills help colleagues find the right person.
      </p>
      <div class="note">
        <h2>One save, together</h2>
        <p>
          Profile details and skill choices save as one change. If someone edits
          your profile in another tab, reload before saving again.
        </p>
      </div>
    </div>
    <form v-if="profile" class="panel profile-form" @submit.prevent="save">
      <div class="form-heading">
        <h2>Profile details</h2>
        <span>Revision {{ revision }}</span>
      </div>
      <label
        >Display name<input
          v-model="displayName"
          required
          maxlength="80" /></label
      ><label
        >Location<input
          v-model="location"
          maxlength="80"
          placeholder="City or region" /></label
      ><label
        >Biography<textarea
          v-model="biography"
          maxlength="1000"
          rows="4"
          placeholder="What do you work on?"
        ></textarea
        ><small>{{ biography.length }} / 1000 characters</small></label
      >
      <fieldset>
        <legend>
          Skills <span>{{ skillIds.length }} / 6 selected</span>
        </legend>
        <p>Choose up to six from the shared list.</p>
        <div class="skill-options">
          <label v-for="s in skills" :key="s.id"
            ><input
              v-model="skillIds"
              type="checkbox"
              :value="s.id"
              :disabled="!skillIds.includes(s.id) && skillIds.length >= 6"
            />{{ s.name }}</label
          >
        </div>
      </fieldset>
      <p v-if="message" :class="isError ? 'error' : 'success'" role="status">
        {{ message }}
      </p>
      <div class="actions">
        <button class="primary" :disabled="busy">
          {{ busy ? "Saving…" : "Save profile" }}</button
        ><button type="button" :disabled="busy" @click="reload">
          Reload latest
        </button>
      </div>
    </form>
    <p v-else-if="error" class="error" role="alert">{{ errorMessage }}</p>
  </section>
</template>
