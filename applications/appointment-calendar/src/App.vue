<script setup lang="ts">
import { onMounted } from "vue";
import InputText from "primevue/inputtext";
import Button from "primevue/button";
import { useWorkshop } from "./store";
const workshop = useWorkshop();
onMounted(() => workshop.load());
</script>
<template>
  <header>
    <div>
      <span class="eyebrow">WORKSHOP OPERATIONS</span>
      <h1>Bay planner</h1>
    </div>
    <nav>
      <RouterLink to="/calendar">Appointments</RouterLink
      ><RouterLink to="/utilization">Utilization</RouterLink>
    </nav>
  </header>
  <main>
    <section class="toolbar">
      <div>
        <label for="day">Workshop day</label
        ><InputText
          id="day"
          type="date"
          :disabled="workshop.busy"
          v-model="workshop.date"
          @change="workshop.load()"
        />
      </div>
      <p>
        Europe/London · 09:00–17:00<br /><small
          >Fixed service durations, shared bay availability</small
        >
      </p>
      <Button
        label="Reload appointments"
        severity="secondary"
        :disabled="workshop.busy || workshop.loading"
        @click="workshop.load()"
      />
    </section>
    <p v-if="workshop.error" role="alert" class="feedback error">
      {{ workshop.error }}
    </p>
    <p v-if="workshop.message" role="status" class="feedback">
      {{ workshop.message }}
    </p>
    <p v-if="workshop.loading" role="status">Loading the selected day…</p>
    <RouterView />
  </main>
</template>
