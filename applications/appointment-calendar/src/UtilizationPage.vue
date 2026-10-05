<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref, watch } from "vue";
import {
  Chart,
  BarController,
  BarElement,
  CategoryScale,
  LinearScale,
  Tooltip,
  Legend,
} from "chart.js";
import { useWorkshop } from "./store";
Chart.register(
  BarController,
  BarElement,
  CategoryScale,
  LinearScale,
  Tooltip,
  Legend,
);
const workshop = useWorkshop();
const canvas = ref<HTMLCanvasElement>();
let chart: Chart | undefined;
const total = computed(
  () =>
    workshop.data?.utilization.reduce(
      (sum, bay) => sum + bay.bookedMinutes,
      0,
    ) ?? 0,
);
function draw() {
  chart?.destroy();
  chart = undefined;
  if (!canvas.value || !workshop.data) return;
  chart = new Chart(canvas.value, {
    type: "bar",
    data: {
      labels: workshop.data.utilization.map((b) => b.name),
      datasets: [
        {
          label: "Booked minutes",
          data: workshop.data.utilization.map((b) => b.bookedMinutes),
          backgroundColor: "#247b68",
          borderRadius: 8,
        },
      ],
    },
    options: {
      animation: false,
      responsive: true,
      maintainAspectRatio: false,
      scales: { y: { beginAtZero: true, suggestedMax: 480 } },
    },
  });
}
onMounted(draw);
watch(() => workshop.data, draw);
onBeforeUnmount(() => chart?.destroy());
</script>
<template>
  <section class="card">
    <div class="card-title">
      <div>
        <h2>Stored utilization</h2>
        <p>
          Booked minutes for {{ workshop.date }}, calculated from Postgres
          appointments.
        </p>
      </div>
      <strong v-if="workshop.current" class="total">{{ total }} minutes</strong>
    </div>
    <p v-if="!workshop.current">
      {{
        workshop.loading
          ? "Loading utilization…"
          : "Utilization unavailable. Reload the selected day."
      }}
    </p>
    <div v-show="workshop.current" class="chart">
      <canvas
        ref="canvas"
        aria-label="Booked minutes by service bay"
        role="img"
      ></canvas>
    </div>
    <table v-if="workshop.current">
      <thead>
        <tr>
          <th>Service bay</th>
          <th>Booked minutes</th>
          <th>Available minutes</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="bay in workshop.data?.utilization" :key="bay.bayId">
          <td>{{ bay.name }}</td>
          <td>{{ bay.bookedMinutes }}</td>
          <td>{{ 480 - bay.bookedMinutes }}</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
