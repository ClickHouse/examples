export default defineNuxtConfig({
  compatibilityDate: "2026-10-02",
  modules: ["nuxt-auth-utils"],
  css: ["~/assets/main.css"],
  devtools: { enabled: false },
  runtimeConfig: {
    appOrigin: "",
    sessionSecure: true,
    session: {
      maxAge: 7200,
      cookie: { httpOnly: true, sameSite: "lax", secure: true },
    },
  },
  app: {
    head: {
      title: "Team directory",
      meta: [
        {
          name: "description",
          content: "A small directory for a trusted team.",
        },
      ],
    },
  },
});
