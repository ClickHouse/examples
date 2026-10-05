<script setup lang="ts">
import { computed, watch } from "vue";
import { useForm } from "vee-validate";
import { toTypedSchema } from "@vee-validate/zod";
import { z } from "zod";
import { Temporal } from "temporal-polyfill";
import Dialog from "primevue/dialog";
import InputText from "primevue/inputtext";
import Textarea from "primevue/textarea";
import Select from "primevue/select";
import Button from "primevue/button";
import { useWorkshop } from "./store";
import { ZONE } from "../shared/contract.js";
const workshop = useWorkshop();
const selected = computed(() =>
  workshop.data?.appointments.find((a) => a.id === workshop.selectedId),
);
const visible = computed({
  get: () => workshop.selectedId !== null,
  set: (value) => {
    if (!value) workshop.selectedId = null;
  },
});
const { defineField, errors, handleSubmit, resetForm } = useForm({
  validationSchema: toTypedSchema(
    z.object({
      customer: z
        .string()
        .trim()
        .min(2, "Enter at least two characters.")
        .max(60),
      note: z.string().max(300),
      bayId: z.number().int().min(1).max(3),
      serviceId: z.number().int().positive(),
      starts: z.string().min(16, "Choose a start time."),
    }),
  ),
});
const [customer] = defineField("customer");
const [note] = defineField("note");
const [bayId] = defineField("bayId");
const [serviceId] = defineField("serviceId");
const [starts] = defineField("starts");
watch(selected, (appointment) => {
  if (appointment)
    resetForm({
      values: {
        customer: appointment.customer,
        note: appointment.note,
        bayId: appointment.bayId,
        serviceId: appointment.serviceId,
        starts: Temporal.Instant.from(appointment.startsAt)
          .toZonedDateTimeISO(ZONE)
          .toPlainDateTime()
          .toString({ smallestUnit: "minute" }),
      },
    });
});
const submit = handleSubmit(async (values) => {
  if (!selected.value) return;
  let startsAt: string;
  try {
    startsAt = Temporal.PlainDateTime.from(values.starts)
      .toZonedDateTime(ZONE, { disambiguation: "reject" })
      .toInstant()
      .toString();
  } catch {
    workshop.error = "Choose a valid workshop time.";
    return;
  }
  if (
    await workshop.save(selected.value.id, {
      revision: selected.value.revision,
      customer: values.customer,
      note: values.note,
      bayId: values.bayId,
      serviceId: values.serviceId,
      startsAt,
    })
  )
    workshop.selectedId = null;
});
</script>
<template>
  <Dialog
    v-model:visible="visible"
    modal
    header="Appointment details"
    :style="{ width: '32rem' }"
    ><form @submit="submit" class="appointment-form">
      <label for="customer">Customer</label
      ><InputText id="customer" v-model="customer" /><small
        v-if="errors.customer"
        class="error"
        >{{ errors.customer }}</small
      >
      <label for="service">Service</label
      ><Select
        inputId="service"
        v-model="serviceId"
        :options="workshop.data?.services ?? []"
        optionLabel="name"
        optionValue="id"
      /><small>Duration comes from the saved service catalogue.</small>
      <label for="edit-bay">Service bay</label
      ><Select
        inputId="edit-bay"
        v-model="bayId"
        :options="workshop.data?.bays ?? []"
        optionLabel="name"
        optionValue="id"
      />
      <label for="starts">Start in Europe/London</label
      ><InputText
        id="starts"
        type="datetime-local"
        step="900"
        v-model="starts"
      /><small v-if="errors.starts" class="error">{{ errors.starts }}</small>
      <label for="note">Workshop note</label
      ><Textarea id="note" v-model="note" rows="3" /><small
        v-if="errors.note"
        class="error"
        >{{ errors.note }}</small
      >
      <p v-if="workshop.error" role="alert" class="error">
        {{ workshop.error }}
      </p>
      <div class="actions">
        <Button
          type="button"
          label="Cancel"
          severity="secondary"
          @click="visible = false"
        /><Button
          type="submit"
          label="Save appointment"
          :loading="workshop.busy"
          :disabled="!workshop.current"
        />
      </div></form
  ></Dialog>
</template>
