<script setup lang="ts">
const { user, clear } = useUserSession();
const leaving = ref(false);
async function signOut() {
  leaving.value = true;
  try {
    await clear();
    await navigateTo("/login");
  } finally {
    leaving.value = false;
  }
}
</script>
<template>
  <div class="shell">
    <header class="site-header">
      <NuxtLink to="/" class="brand"
        ><span class="brand-mark">T</span>Team directory</NuxtLink
      >
      <nav v-if="user">
        <NuxtLink to="/">Directory</NuxtLink
        ><NuxtLink to="/profile">My profile</NuxtLink
        ><button class="quiet" :disabled="leaving" @click="signOut">
          Sign out
        </button>
      </nav>
    </header>
    <main><NuxtPage /></main>
    <footer>A shared place for your team</footer>
  </div>
</template>
