<script setup lang="ts">
const { loggedIn, fetch: fetchSession } = useUserSession();
if (loggedIn.value) await navigateTo("/");
const email = ref("");
const password = ref("");
const busy = ref(false);
const message = ref("");
async function signIn() {
  busy.value = true;
  message.value = "";
  try {
    await $fetch("/api/auth/login", {
      method: "POST",
      body: { email: email.value, password: password.value },
    });
    await fetchSession();
    await navigateTo("/");
  } catch (error: any) {
    message.value =
      error.data?.statusMessage || "Sign-in failed. Please try again.";
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section class="login-layout">
    <div>
      <p class="eyebrow">People, connected</p>
      <h1>Find the person<br />behind the skill.</h1>
      <p class="intro">
        A shared place to find colleagues, discover what they work on, and keep
        your own profile up to date.
      </p>
      <div class="sample-tags">
        <span>Postgres</span><span>Design</span><span>Support</span>
      </div>
    </div>
    <form class="panel sign-in" @submit.prevent="signIn">
      <p class="eyebrow">Trusted team access</p>
      <h2>Sign in</h2>
      <p>Use the account your directory operator provided.</p>
      <label
        >Email<input
          v-model="email"
          type="email"
          autocomplete="username"
          required
          maxlength="254" /></label
      ><label
        >Password<input
          v-model="password"
          type="password"
          autocomplete="current-password"
          required
          maxlength="256"
      /></label>
      <p v-if="message" class="error" role="alert">{{ message }}</p>
      <button class="primary" :disabled="busy">
        {{ busy ? "Signing in…" : "Sign in" }}
      </button>
    </form>
  </section>
</template>
