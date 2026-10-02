<script>
  let { data } = $props();
  import { createAuthClient } from "better-auth/svelte";
  const authClient = createAuthClient();
  let signup = $state(false);
  let message = $state("");
  let busy = $state(false);
  async function submit(event) {
    event.preventDefault();
    busy = true;
    message = "";
    const values = Object.fromEntries(new FormData(event.currentTarget));
    try {
      const result = signup
        ? await authClient.signUp.email({
            email: values.email,
            password: values.password,
            name: values.name,
          })
        : await authClient.signIn.email({
            email: values.email,
            password: values.password,
          });
      if (result.error) message = result.error.message ?? "Could not sign in";
      else window.location.assign("/");
    } catch {
      message = "Could not connect. Try again.";
    } finally {
      busy = false;
    }
  }
</script>

<section class="auth">
  <p class="eyebrow">WELCOME TO READING ROOM</p>
  <h1>
    {signup ? "Make room for good ideas." : "Pick up where you left off."}
  </h1>
  <p>Sign in to save, tag and browse the shared collection.</p>
  {#if message}<p role="alert" class="error">{message}</p>{/if}
  <form onsubmit={submit}>
    {#if signup}<label
        >Your name<input
          name="name"
          required
          maxlength="100"
          autocomplete="name"
        /></label
      >{/if}<label
      >Email<input
        name="email"
        type="email"
        required
        autocomplete="email"
      /></label
    ><label
      >Password<input
        name="password"
        type="password"
        required
        minlength="12"
        autocomplete={signup ? "new-password" : "current-password"}
      /></label
    ><button disabled={busy}
      >{busy ? "Please wait…" : signup ? "Create account" : "Sign in"}</button
    >
  </form>
  {#if data.signupEnabled}<button
      class="quiet"
      onclick={() => {
        signup = !signup;
        message = "";
      }}
      >{signup
        ? "Already have an account? Sign in"
        : "Create an account"}</button
    >{:else}<p>
      Account creation is closed. Ask the collection owner for access.
    </p>{/if}
</section>
