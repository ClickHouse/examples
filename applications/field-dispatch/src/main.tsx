import { createRoot } from "react-dom/client";
import { useCallback, useEffect, useRef, useState } from "react";
import { area, booleanPointInPolygon, distance, point } from "@turf/turf";
import { MapView } from "./MapView";
import type { Bootstrap, Job, MapState, Viewport } from "./domain";
import "./styles.css";

async function api<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(path, options);
  const value = await response.json();
  if (!response.ok)
    throw new Error(value.error ?? "The request could not be completed.");
  return value as T;
}
function App() {
  const [data, setData] = useState<Bootstrap | null>(null);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [total, setTotal] = useState(0);
  const [capped, setCapped] = useState(false);
  const [jobsStatus, setJobsStatus] = useState<"loading" | "ready" | "error">(
    "loading",
  );
  const [selectedJob, setSelectedJob] = useState<string | null>(null);
  const [areaId, setAreaId] = useState("");
  const [mode, setMode] = useState<MapState["mode"]>("assignments");
  const [camera, setCamera] = useState<Pick<
    MapState,
    "longitude" | "latitude" | "zoom"
  > | null>(null);
  const [savedRevision, setSavedRevision] = useState(1);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const viewport = useRef<Viewport | null>(null);
  const request = useRef<AbortController | null>(null);
  const fetchJobs = useCallback((bounds: Viewport) => {
    viewport.current = bounds;
    setJobs([]);
    setTotal(0);
    setCapped(false);
    setJobsStatus("loading");
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    const query = new URLSearchParams(
      Object.entries(bounds).map(([key, value]) => [key, String(value)]),
    );
    void api<{ jobs: Job[]; total: number; capped: boolean }>(
      `/api/jobs?${query}`,
      { signal: controller.signal },
    )
      .then((result) => {
        if (controller.signal.aborted) return;
        setJobs(result.jobs);
        setTotal(result.total);
        setCapped(result.capped);
        setJobsStatus("ready");
        setError("");
      })
      .catch((err) => {
        if (!controller.signal.aborted) {
          setError(err.message);
          setJobsStatus("error");
        }
      });
  }, []);
  useEffect(() => {
    let active = true;
    void api<Bootstrap>("/api/bootstrap")
      .then((value) => {
        if (!active) return;
        setData(value);
        setAreaId(value.state.areaId);
        setMode(value.state.mode);
        setSavedRevision(value.state.revision);
      })
      .catch((err) => {
        if (active) setError(err.message);
      });
    return () => {
      active = false;
      request.current?.abort();
    };
  }, []);
  const service = data?.areas.find((value) => value.id === areaId);
  const team = data?.teams.find((value) => value.areaId === areaId);
  const job = jobs.find((value) => value.id === selectedJob);
  const inside = !!(
    service &&
    job &&
    booleanPointInPolygon(point(job.position), service.feature)
  );
  const previewArea = service ? area(service.feature) / 1_000_000 : 0;
  const previewDistance =
    job && team
      ? distance(point(team.position), point(job.position), {
          units: "kilometers",
        })
      : 0;
  async function assignJob() {
    if (!job || !team) return;
    setBusy(true);
    setMessage("");
    setError("");
    try {
      await api("/api/assign", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          jobId: job.id,
          teamId: team.id,
          revision: job.revision,
        }),
      });
      if (viewport.current) fetchJobs(viewport.current);
      setMessage(`${team.name} assigned to ${job.code}.`);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function saveView() {
    if (!camera) return;
    setBusy(true);
    setMessage("");
    setError("");
    try {
      const result = await api<{ revision: number }>("/api/map", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          ...camera,
          areaId,
          mode,
          revision: savedRevision,
        }),
      });
      setSavedRevision(result.revision);
      setMessage(
        "Map view saved. Reload to restore this area, camera and layer.",
      );
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <main>
      <header>
        <div>
          <p className="eyebrow">FIELD OPERATIONS / MAINTENANCE DESK</p>
          <h1>A place for every job.</h1>
          <p className="intro">
            Review the work in view, check service coverage and send the right
            crew.
          </p>
        </div>
        <span className="edition">
          Synthetic town
          <br />
          Morning dispatch
        </span>
      </header>
      <div className="toolbar">
        <label>
          Service area
          <select
            value={areaId}
            onChange={(event) => setAreaId(event.target.value)}
            disabled={!data || busy}
          >
            {data?.areas.map((value) => (
              <option key={value.id} value={value.id}>
                {value.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Map layer
          <select
            value={mode}
            onChange={(event) =>
              setMode(event.target.value as MapState["mode"])
            }
            disabled={busy}
          >
            <option value="assignments">Crew assignments</option>
            <option value="priority">Job priority</option>
          </select>
        </label>
        <div className="coverage">
          <span>AREA PREVIEW</span>
          <strong>{previewArea.toFixed(2)} km²</strong>
        </div>
        <button className="save" onClick={saveView} disabled={!camera || busy}>
          Save map view
        </button>
      </div>
      {message && (
        <p role="status" className="notice success">
          {message}
        </p>
      )}
      {error && (
        <p role="alert" className="notice failure">
          {error}
        </p>
      )}
      <section className="desk">
        <aside>
          <div className="panel-heading">
            <span className="eyebrow">01 / WORK IN VIEW</span>
            <h2>
              {jobsStatus === "loading"
                ? "Loading jobs…"
                : jobsStatus === "error"
                  ? "Jobs unavailable"
                  : `${total} maintenance jobs`}
            </h2>
            <p>
              {jobsStatus === "ready"
                ? capped
                  ? "Showing the first 100 jobs in this viewport."
                  : "This list follows the current map viewport."
                : "Results appear after the current viewport finishes loading."}
            </p>
            <button
              onClick={() => viewport.current && fetchJobs(viewport.current)}
              disabled={jobsStatus === "loading"}
            >
              Refresh jobs
            </button>
          </div>
          <div className="jobs" aria-label="Jobs in the map viewport">
            {jobs.map((value) => {
              const assigned = data?.teams.find((t) => t.id === value.teamId);
              return (
                <button
                  key={value.id}
                  className={`job ${selectedJob === value.id ? "selected" : ""}`}
                  onClick={() => {
                    setSelectedJob(value.id);
                    setMessage("");
                    setError("");
                  }}
                  aria-pressed={selectedJob === value.id}
                >
                  <span className="job-top">
                    <strong>{value.code}</strong>
                    <span className={`priority ${value.priority}`}>
                      {value.priority}
                    </span>
                  </span>
                  <span className="job-title">{value.title}</span>
                  <span className="assignment">
                    {assigned?.name ?? "Unassigned"}
                  </span>
                </button>
              );
            })}
          </div>
        </aside>
        <div className="map-column">
          {data ? (
            <MapView
              data={data}
              jobs={jobs}
              selectedJob={selectedJob}
              areaId={areaId}
              mode={mode}
              onJob={setSelectedJob}
              onViewport={fetchJobs}
              onCamera={setCamera}
              onError={setError}
            />
          ) : (
            <div className="loading">Loading the saved dispatch view…</div>
          )}
          <div className="legend">
            <span>
              <i className="swatch unassigned" />
              Unassigned / routine
            </span>
            {mode === "assignments" ? (
              data?.teams.map((t) => (
                <span key={t.id}>
                  <i
                    className="swatch"
                    style={{
                      background: data.areas.find((a) => a.id === t.areaId)
                        ?.color,
                    }}
                  />
                  {t.name}
                </span>
              ))
            ) : (
              <span>
                <i className="swatch urgent" />
                Urgent work
              </span>
            )}
            <small>
              Lines link assigned jobs to crew depots; they are not road routes.
            </small>
          </div>
          <div className="review-panel">
            <div>
              <span className="eyebrow">02 / COVERAGE BEFORE COMMIT</span>
              <h2>
                {job
                  ? `${job.code} · ${job.title}`
                  : "Select a job on the map or in the list"}
              </h2>
              {job && (
                <p>
                  {inside ? "Inside" : "Outside"} {service?.name} ·{" "}
                  {previewDistance.toFixed(2)} km straight-line from{" "}
                  {team?.name} depot.
                </p>
              )}
              <p className="hint">
                The browser previews coverage. PostGIS checks the stored
                boundary before saving.
              </p>
            </div>
            <button
              onClick={assignJob}
              disabled={!job || !inside || busy || job.teamId === team?.id}
            >
              Assign {team?.name ?? "crew"}
            </button>
          </div>
        </div>
      </section>
      <footer>
        Field dispatch · Fictional jobs and service boundaries · Coordinates
        [longitude, latitude], SRID 4326
      </footer>
    </main>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
