import { createApp } from "vue";
import { createPinia } from "pinia";
import { createRouter, createWebHistory } from "vue-router";
import PrimeVue from "primevue/config";
import Aura from "@primeuix/themes/aura";
import App from "./App.vue";
import CalendarPage from "./CalendarPage.vue";
import UtilizationPage from "./UtilizationPage.vue";
import "./style.css";
const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: "/", redirect: "/calendar" },
    { path: "/calendar", component: CalendarPage },
    { path: "/utilization", component: UtilizationPage },
  ],
});
createApp(App)
  .use(createPinia())
  .use(router)
  .use(PrimeVue, {
    theme: { preset: Aura, options: { darkModeSelector: false } },
  })
  .mount("#app");
