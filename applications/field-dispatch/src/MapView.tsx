import { useEffect, useRef, useState } from "react";
import {
  Map,
  NavigationControl,
  addProtocol,
  removeProtocol,
  setWorkerUrl,
} from "maplibre-gl";
import workerUrl from "maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url";
import { Protocol } from "pmtiles";
import { MapLibreOverlay } from "@deck.gl/maplibre";
import { ArcLayer, ScatterplotLayer } from "@deck.gl/layers";
import type { Color } from "@deck.gl/core";
import type { Bootstrap, Job, MapState, Viewport } from "./domain";
import "maplibre-gl/dist/maplibre-gl.css";

setWorkerUrl(workerUrl);
function rgb(hex: string): Color {
  return [
    parseInt(hex.slice(1, 3), 16),
    parseInt(hex.slice(3, 5), 16),
    parseInt(hex.slice(5, 7), 16),
    230,
  ];
}
type Props = {
  data: Bootstrap;
  jobs: Job[];
  selectedJob: string | null;
  areaId: string;
  mode: MapState["mode"];
  onJob: (id: string) => void;
  onViewport: (bounds: Viewport) => void;
  onCamera: (camera: Pick<MapState, "longitude" | "latitude" | "zoom">) => void;
  onError: (message: string) => void;
};
export function MapView(props: Props) {
  const container = useRef<HTMLDivElement>(null);
  const mapRef = useRef<Map | null>(null);
  const overlayRef = useRef<MapLibreOverlay | null>(null);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    const protocol = new Protocol();
    addProtocol("pmtiles", protocol.tile);
    const map = new Map({
      container: container.current!,
      center: [props.data.state.longitude, props.data.state.latitude],
      zoom: props.data.state.zoom,
      minZoom: 12,
      maxZoom: 16,
      maxBounds: [
        [-1.51, 53.33],
        [-1.41, 53.41],
      ],
      dragRotate: false,
      pitchWithRotate: false,
      touchPitch: false,
      canvasContextAttributes: { preserveDrawingBuffer: true, antialias: true },
      style: {
        version: 8,
        sources: {
          town: {
            type: "vector",
            url: `pmtiles://${location.origin}/maintenance-town.pmtiles`,
            attribution: "Synthetic map data · ClickHouse examples",
          },
        },
        layers: [
          {
            id: "paper",
            type: "background",
            paint: { "background-color": "#eff0e5" },
          },
          {
            id: "blocks",
            type: "fill",
            source: "town",
            "source-layer": "land",
            filter: ["==", ["get", "kind"], "block"],
            paint: { "fill-color": "#d8d4c3", "fill-opacity": 0.7 },
          },
          {
            id: "parks",
            type: "fill",
            source: "town",
            "source-layer": "land",
            filter: ["==", ["get", "kind"], "park"],
            paint: { "fill-color": "#c0d2a4" },
          },
          {
            id: "river",
            type: "line",
            source: "town",
            "source-layer": "water",
            paint: { "line-color": "#8cb7c3", "line-width": 7 },
          },
          {
            id: "roads",
            type: "line",
            source: "town",
            "source-layer": "roads",
            paint: {
              "line-color": "#faf9f2",
              "line-width": ["case", ["==", ["get", "kind"], "main"], 5, 3],
            },
          },
        ],
      },
    });
    mapRef.current = map;
    map.addControl(new NavigationControl({ showCompass: false }), "top-right");
    const captureView = () => {
      const bounds = map.getBounds();
      props.onViewport({
        west: bounds.getWest(),
        south: bounds.getSouth(),
        east: bounds.getEast(),
        north: bounds.getNorth(),
      });
      const center = map.getCenter();
      props.onCamera({
        longitude: center.lng,
        latitude: center.lat,
        zoom: map.getZoom(),
      });
    };
    map.on("load", () => {
      map.addSource("areas", {
        type: "geojson",
        data: {
          type: "FeatureCollection",
          features: props.data.areas.map((area) => ({
            ...area.feature,
            properties: { ...area.feature.properties, color: area.color },
          })),
        },
      });
      map.addLayer({
        id: "service-fill",
        type: "fill",
        source: "areas",
        paint: { "fill-color": ["get", "color"], "fill-opacity": 0.07 },
      });
      map.addLayer({
        id: "service-outline",
        type: "line",
        source: "areas",
        paint: {
          "line-color": ["get", "color"],
          "line-width": 2,
          "line-dasharray": [4, 2],
        },
      });
      const overlay = new MapLibreOverlay({ interleaved: true, layers: [] });
      map.addControl(overlay);
      overlayRef.current = overlay;
      map.on("click", (event) => {
        const picked = overlay.pickObject({
          x: event.point.x,
          y: event.point.y,
          radius: 5,
          layerIds: ["maintenance-jobs"],
        });
        if (picked?.object) props.onJob((picked.object as Job).id);
      });
      setReady(true);
      captureView();
    });
    map.on("moveend", captureView);
    map.on("error", () =>
      props.onError(
        "The map could not render. Check WebGL and the local basemap archive.",
      ),
    );
    return () => {
      setReady(false);
      overlayRef.current?.finalize();
      overlayRef.current = null;
      map.remove();
      mapRef.current = null;
      removeProtocol("pmtiles");
    };
  }, [props.data, props.onViewport, props.onCamera, props.onError]);
  useEffect(() => {
    if (!ready || !mapRef.current) return;
    mapRef.current.setPaintProperty("service-fill", "fill-opacity", [
      "case",
      ["==", ["get", "id"], props.areaId],
      0.2,
      0.04,
    ]);
    mapRef.current.setPaintProperty("service-outline", "line-width", [
      "case",
      ["==", ["get", "id"], props.areaId],
      3,
      1,
    ]);
  }, [ready, props.areaId]);
  useEffect(() => {
    if (!ready || !overlayRef.current) return;
    const teams = new globalThis.Map(
      props.data.teams.map((team) => [team.id, team]),
    );
    const areas = new globalThis.Map(
      props.data.areas.map((area) => [area.id, area]),
    );
    const color = (job: Job): Color =>
      props.mode === "priority"
        ? job.priority === "urgent"
          ? [178, 86, 42, 240]
          : [88, 105, 120, 220]
        : job.teamId
          ? rgb(areas.get(teams.get(job.teamId)!.areaId)!.color)
          : [93, 103, 113, 235];
    overlayRef.current.setProps({
      layers: [
        new ArcLayer<Job>({
          id: "assignment-links",
          data:
            props.mode === "assignments"
              ? props.jobs.filter((job) => job.teamId && teams.has(job.teamId))
              : [],
          getSourcePosition: (job) => teams.get(job.teamId!)!.position,
          getTargetPosition: (job) => job.position,
          getSourceColor: color,
          getTargetColor: color,
          getWidth: 2,
          getHeight: 0.12,
          pickable: false,
        }),
        new ScatterplotLayer<Job>({
          id: "maintenance-jobs",
          data: props.jobs,
          pickable: true,
          getPosition: (job) => job.position,
          getFillColor: color,
          getRadius: (job) => (job.priority === "urgent" ? 34 : 24),
          radiusMinPixels: 7,
          radiusMaxPixels: 18,
          stroked: true,
          getLineColor: (job) =>
            job.id === props.selectedJob
              ? [255, 255, 255, 255]
              : [49, 65, 71, 220],
          getLineWidth: (job) => (job.id === props.selectedJob ? 4 : 1),
          lineWidthUnits: "pixels",
          updateTriggers: {
            getFillColor: [props.mode],
            getLineColor: [props.selectedJob],
            getLineWidth: [props.selectedJob],
          },
        }),
      ],
    });
  }, [
    ready,
    props.data,
    props.jobs,
    props.selectedJob,
    props.mode,
    props.onJob,
  ]);
  return (
    <div className="map-frame">
      <div
        ref={container}
        className="map"
        aria-label="Maintenance dispatch map"
      />
      <span className="map-status">
        {ready ? "Map ready · Synthetic town" : "Loading local map…"}
      </span>
    </div>
  );
}
