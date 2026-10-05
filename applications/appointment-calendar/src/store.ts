import { defineStore } from "pinia";
import { initClient } from "@ts-rest/core";
import { contract, type Day, type Update } from "../shared/contract.js";
const client = initClient(contract, {
  baseUrl: window.location.origin,
  baseHeaders: { "X-Workshop-Calendar": "1" },
});
const responseError = (body: unknown) =>
  typeof body === "object" && body !== null && "message" in body
    ? String(body.message)
    : "Unexpected server response.";
export const useWorkshop = defineStore("workshop", {
  state: () => ({
    date: "2026-10-05",
    bayId: 1,
    selectedId: null as number | null,
    data: null as Day | null,
    busy: false,
    loading: false,
    request: 0,
    error: "",
    message: "",
  }),
  getters: {
    current: (state) => !state.loading && state.data?.date === state.date,
  },
  actions: {
    async load() {
      const date = this.date,
        request = ++this.request;
      this.loading = true;
      this.error = "";
      if (this.data?.date !== date) {
        this.data = null;
        this.selectedId = null;
      }
      try {
        const result = await client.day({ query: { date } });
        if (request !== this.request || date !== this.date) return false;
        if (result.status !== 200) throw new Error(responseError(result.body));
        this.data = result.body;
        return true;
      } catch (error) {
        if (request === this.request && date === this.date)
          this.error =
            error instanceof Error
              ? error.message
              : "Could not load appointments.";
        return false;
      } finally {
        if (request === this.request) this.loading = false;
      }
    },
    async save(id: number, body: Update) {
      if (this.busy || !this.current) {
        this.error = "Wait for the selected day to load.";
        return false;
      }
      this.busy = true;
      this.error = "";
      this.message = "";
      try {
        const result = await client.update({
          params: { id: String(id) },
          body,
        });
        if (result.status !== 200) {
          this.error = responseError(result.body);
          return false;
        }
        this.data = null;
        const refreshed = await this.load();
        this.message = refreshed
          ? "Appointment saved."
          : "Appointment saved, but the calendar refresh failed. Reload before editing again.";
        return true;
      } catch {
        this.error =
          "Could not save the appointment. Reload before trying again.";
        return false;
      } finally {
        this.busy = false;
      }
    },
  },
});
