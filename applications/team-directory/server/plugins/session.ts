export default defineNitroPlugin(() => {
  if (
    !process.env.NUXT_SESSION_PASSWORD ||
    process.env.NUXT_SESSION_PASSWORD.length < 32
  )
    throw new Error(
      "Set a private NUXT_SESSION_PASSWORD of at least 32 characters.",
    );
  sessionHooks.hook("fetch", async (_session, event) => {
    await apiResult(() => activeIdentity(event));
  });
});
