<script setup lang="ts">
import { computed, ref, watch } from "vue";
import FullCalendar from "@fullcalendar/vue3";
import timeGridPlugin from "@fullcalendar/vue3/timegrid";
import interactionPlugin from "@fullcalendar/vue3/interaction";
import themePlugin from "@fullcalendar/vue3/themes/monarch";
import type { CalendarOptions } from "@fullcalendar/vue3";
import "@fullcalendar/vue3/skeleton.css";
import "@fullcalendar/vue3/themes/monarch/theme.css";
import "@fullcalendar/vue3/themes/monarch/palettes/purple.css";
import Select from "primevue/select";
import AppointmentDialog from "./AppointmentDialog.vue";
import { useWorkshop } from "./store";
import { ZONE } from "../shared/contract.js";
const workshop = useWorkshop();
const calendar = ref<InstanceType<typeof FullCalendar>>();
watch(
  () => workshop.date,
  (date) => calendar.value?.getApi().gotoDate(date),
);
const options = computed<CalendarOptions>(() => ({
  plugins: [timeGridPlugin, interactionPlugin, themePlugin],
  initialView: "timeGridDay",
  initialDate: workshop.date,
  timeZone: ZONE,
  headerToolbar: false,
  allDaySlot: false,
  slotMinTime: "09:00:00",
  slotMaxTime: "17:00:00",
  slotDuration: "00:15:00",
  snapDuration: "00:15:00",
  height: 650,
  editable: workshop.current && !workshop.busy && workshop.selectedId === null,
  eventDurationEditable: false,
  events: (workshop.data?.date === workshop.date
    ? workshop.data.appointments
    : []
  )
    .filter((a) => a.bayId === workshop.bayId)
    .map((a) => ({
      id: String(a.id),
      title: `${a.customer} · ${a.serviceName}`,
      start: a.startsAt,
      end: a.endsAt,
    })),
  eventClick: (info) => {
    if (!workshop.current || workshop.busy) return;
    workshop.selectedId = Number(info.event.id);
  },
  eventDrop: async (info) => {
    const stored = workshop.data?.appointments.find(
      (a) => a.id === Number(info.event.id),
    );
    if (!stored || !info.event.start) {
      info.revert();
      return;
    }
    const saved = await workshop.save(stored.id, {
      revision: stored.revision,
      bayId: stored.bayId,
      serviceId: stored.serviceId,
      customer: stored.customer,
      note: stored.note,
      startsAt: info.event.start.toISOString(),
    });
    if (!saved) {
      const error = workshop.error;
      info.revert();
      await workshop.load();
      workshop.error = error;
    }
  },
}));
</script>
<template>
  <section class="card">
    <div class="card-title">
      <div>
        <h2>Daily appointments</h2>
        <p>Drag a booking to reschedule, or select it to edit details.</p>
      </div>
      <div>
        <label for="bay">Service bay</label
        ><Select
          inputId="bay"
          v-model="workshop.bayId"
          :options="workshop.data?.bays ?? []"
          optionLabel="name"
          optionValue="id"
        />
      </div>
    </div>
    <FullCalendar ref="calendar" :options="options" />
    <p
      v-if="
        workshop.data &&
        !workshop.data.appointments.some((a) => a.bayId === workshop.bayId)
      "
    >
      No appointments in this bay today.
    </p>
  </section>
  <AppointmentDialog />
</template>
