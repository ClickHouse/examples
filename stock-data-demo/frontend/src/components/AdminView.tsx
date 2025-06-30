"use client";

import { ReactElement, useState, useEffect } from "react";
import {
  Container,
  Panel,
  Title,
  Text,
  Button,
  ButtonGroup,
} from "@clickhouse/click-ui";

interface MetricsData {
  status: string;
  connected: boolean;
  paused: boolean;
  uptime: number;
  totalUptime: number;
  timeSinceLastDisconnect: number | null;
  runningInserts: number;
  queueLength: number;
  memoryUsageMB: number;
  processedMessages: number;
  droppedMessages: number;
  tradesInserted: number;
  quotesInserted: number;
  totalRecordsInserted: number;
  batchSizes: {
    trades: number;
    quotes: number;
  };
  throughput: {
    tradesPerSecond: number;
    quotesPerSecond: number;
    totalPerSecond: number;
  };
  reconnectAttempts: number;
  maxReconnectAttempts: number;
  statusMessage: string;
  connectionHistory: Array<{
    timestamp: string;
    event: string;
    details?: any;
    reconnectAttempts: number;
  }>;
  lastMessageTime: number;
  timeSinceLastMessage: number;
}

export default function AdminView(): ReactElement {
  const [data, setData] = useState<MetricsData | null>(null);
  const [lastUpdated, setLastUpdated] = useState<string>("");
  const [notification, setNotification] = useState<{
    message: string;
    type: "success" | "error";
  } | null>(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const response = await fetch("/metrics");
        const metrics = await response.json();
        setData(metrics);
        setLastUpdated(new Date().toLocaleTimeString());
      } catch (error) {
        console.error("Failed to fetch metrics:", error);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 2000);

    return () => clearInterval(interval);
  }, []);

  const handleControlAction = async (action: string) => {
    try {
      const response = await fetch(`/control/${action}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
      });

      const result = await response.json();

      if (result.success) {
        setNotification({ message: result.message, type: "success" });
        setTimeout(() => setNotification(null), 3000);
      } else {
        setNotification({ message: "Action failed", type: "error" });
        setTimeout(() => setNotification(null), 3000);
      }
    } catch (error) {
      console.error("Control action failed:", error);
      setNotification({ message: "Network error", type: "error" });
      setTimeout(() => setNotification(null), 3000);
    }
  };

  const formatUptime = (seconds: number): string => {
    if (!seconds || seconds < 0) return "--";

    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);

    if (hours > 0) {
      return `${hours}h ${minutes}m ${secs}s`;
    } else if (minutes > 0) {
      return `${minutes}m ${secs}s`;
    } else {
      return `${secs}s`;
    }
  };

  const formatNumber = (num: number): string => {
    if (num === undefined || num === null) return "--";

    if (num >= 1000000) {
      return (num / 1000000).toFixed(1) + "M";
    } else if (num >= 1000) {
      return (num / 1000).toFixed(1) + "K";
    } else {
      return num.toLocaleString();
    }
  };

  const getStatusBadge = () => {
    if (!data)
      return (
        <Text
          style={{
            padding: "4px 8px",
            borderRadius: "4px",
            backgroundColor: "var(--color-background-muted)",
          }}
        >
          Loading
        </Text>
      );

    if (data.paused) {
      return (
        <Text
          style={{
            padding: "4px 8px",
            borderRadius: "4px",
            backgroundColor: "var(--color-warning-background)",
            color: "var(--color-warning-foreground)",
          }}
        >
          PAUSED
        </Text>
      );
    } else if (data.connected) {
      return (
        <Text
          style={{
            padding: "4px 8px",
            borderRadius: "4px",
            backgroundColor: "var(--color-success-background)",
            color: "var(--color-success-foreground)",
          }}
        >
          CONNECTED
        </Text>
      );
    } else {
      return (
        <Text
          style={{
            padding: "4px 8px",
            borderRadius: "4px",
            backgroundColor: "var(--color-danger-background)",
            color: "var(--color-danger-foreground)",
          }}
        >
          DISCONNECTED
        </Text>
      );
    }
  };

  const formatEventName = (event: string): string => {
    switch (event) {
      case "connected":
        return "Connected";
      case "disconnected":
        return "Disconnected";
      case "error":
        return "Error";
      case "connection_failed":
        return "Connection Failed";
      default:
        return event
          .replace(/_/g, " ")
          .replace(/\b\w/g, (l) => l.toUpperCase());
    }
  };

  const formatTimeSinceMessage = (seconds: number): string => {
    if (seconds < 60) {
      return `${Math.round(seconds)}s ago`;
    } else if (seconds < 3600) {
      return `${Math.round(seconds / 60)}m ago`;
    } else {
      return `${Math.round(seconds / 3600)}h ago`;
    }
  };

  if (!data) {
    return (
      <Container
        fillWidth
        fillHeight
        alignItems="center"
        justifyContent="center"
      >
        <Text>Loading metrics...</Text>
      </Container>
    );
  }

  const buttonOptions = [
    {
      label: "Start",
      value: "start",
    },
    {
      label: "Pause",
      value: "pause",
    },
    {
      label: "Stop",
      value: "stop",
    },
    {
      label: "Restart",
      value: "restart",
    },
  ];

  return (
    <Container fillWidth padding="lg" orientation="vertical" gap="lg">
      {notification && (
        <Panel
          hasBorder
          padding="md"
          fillWidth
          style={{
            backgroundColor:
              notification.type === "success"
                ? "var(--color-success-background)"
                : "var(--color-danger-background)",
            borderColor:
              notification.type === "success"
                ? "var(--color-success)"
                : "var(--color-danger)",
          }}
        >
          <Container
            orientation="horizontal"
            justifyContent="space-between"
            alignItems="center"
          >
            <Text>{notification.message}</Text>
            <Button onClick={() => setNotification(null)}>×</Button>
          </Container>
        </Panel>
      )}

      <Container
        orientation="horizontal"
        justifyContent="space-between"
        alignItems="center"
        fillWidth
      >
        <Title type="h1">📈 Stock Data Ingestion Monitor</Title>
        <Text color="muted">Last updated: {lastUpdated}</Text>
      </Container>

      <Panel hasBorder padding="lg" fillWidth>
        <Container
          orientation="horizontal"
          justifyContent="space-between"
          alignItems="center"
          fillWidth
        >
          <Container orientation="horizontal" alignItems="center" gap="lg">
            <Container orientation="horizontal" alignItems="center" gap="md">
              {getStatusBadge()}
              <Container orientation="vertical" gap="xs">
                <Text weight="semibold">
                  {data.statusMessage || "Initializing..."}
                </Text>
                <Text color="muted" size="sm">
                  {data.paused
                    ? "Data ingestion is paused"
                    : data.connected
                    ? "Active - Receiving data"
                    : "Not connected to data feed"}
                </Text>
              </Container>
            </Container>

            <Container
              orientation="vertical"
              gap="xs"
              style={{ minWidth: "140px" }}
            >
              <Text color="muted" size="sm">
                Current Throughput
              </Text>
              <Container orientation="horizontal" gap="sm">
                <Text size="sm" weight="medium">
                  {data.throughput?.totalPerSecond || 0}/sec
                </Text>
                <Text color="muted" size="xs">
                  ({data.throughput?.tradesPerSecond || 0}T +{" "}
                  {data.throughput?.quotesPerSecond || 0}Q)
                </Text>
              </Container>
            </Container>
          </Container>

          <ButtonGroup
            options={buttonOptions}
            onClick={(value: string) => handleControlAction(value)}
          />
        </Container>
      </Panel>

      <Container orientation="horizontal" gap="lg" fillWidth>
        <Panel hasBorder padding="md" fillWidth>
          <Container orientation="vertical" gap="sm">
            <Text color="muted" size="sm">
              Connection Uptime
            </Text>
            <Title type="h3">{formatUptime(data.uptime)}</Title>
            <Text color="muted" size="xs">
              Total: {formatUptime(data.totalUptime)}
            </Text>
          </Container>
        </Panel>

        <Panel hasBorder padding="md" fillWidth>
          <Container orientation="vertical" gap="sm">
            <Text color="muted" size="sm">
              Trades Inserted
            </Text>
            <Title type="h3">{formatNumber(data.tradesInserted)}</Title>
            <Text color="muted" size="xs">
              Market transactions
            </Text>
          </Container>
        </Panel>

        <Panel hasBorder padding="md" fillWidth>
          <Container orientation="vertical" gap="sm">
            <Text color="muted" size="sm">
              Quotes Inserted
            </Text>
            <Title type="h3">{formatNumber(data.quotesInserted)}</Title>
            <Text color="muted" size="xs">
              Price quotes
            </Text>
          </Container>
        </Panel>
      </Container>

      <Container orientation="horizontal" gap="lg" fillWidth>
        <Panel hasBorder padding="md" fillWidth>
          <Container orientation="vertical" gap="sm">
            <Text color="muted" size="sm">
              Total Records
            </Text>
            <Title type="h3">{formatNumber(data.totalRecordsInserted)}</Title>
            <Text color="muted" size="xs">
              Processed: {formatNumber(data.processedMessages)}
            </Text>
          </Container>
        </Panel>

        <Panel hasBorder padding="md" fillWidth>
          <Container orientation="vertical" gap="sm">
            <Text color="muted" size="sm">
              Memory Usage
            </Text>
            <Title type="h3">{data.memoryUsageMB} MB</Title>
            <Text color="muted" size="xs">
              Dropped: {formatNumber(data.droppedMessages)}
            </Text>
          </Container>
        </Panel>

        <Panel hasBorder padding="md" fillWidth>
          <Container orientation="vertical" gap="sm">
            <Text color="muted" size="sm">
              Database Queue
            </Text>
            <Title type="h3">{data.queueLength}</Title>
            <Text color="muted" size="xs">
              Active inserts: {data.runningInserts}
            </Text>
          </Container>
        </Panel>
      </Container>

      <Container
        orientation="horizontal"
        gap="lg"
        fillWidth
        justifyContent="start"
      >
        <Panel hasBorder padding="lg" style={{ flex: 1 }}>
          <Container orientation="vertical" gap="md">
            <Title type="h4">📊 Performance Metrics</Title>
            <Container orientation="vertical" gap="sm">
              <Container
                orientation="horizontal"
                justifyContent="space-between"
              >
                <Text color="muted">Batch Sizes:</Text>
                <Text>
                  Trades: {data.batchSizes?.trades || 0}, Quotes:{" "}
                  {data.batchSizes?.quotes || 0}
                </Text>
              </Container>
              <Container
                orientation="horizontal"
                justifyContent="space-between"
              >
                <Text color="muted">Last Message:</Text>
                <Text>{formatTimeSinceMessage(data.timeSinceLastMessage)}</Text>
              </Container>
              <Container
                orientation="horizontal"
                justifyContent="space-between"
              >
                <Text color="muted">Reconnect Attempts:</Text>
                <Text>
                  {data.reconnectAttempts} / {data.maxReconnectAttempts}
                </Text>
              </Container>
            </Container>
          </Container>
        </Panel>

        <Panel hasBorder padding="lg" style={{ flex: 1 }}>
          <Container orientation="vertical" gap="md">
            <Title type="h4">📝 Connection History</Title>
            <Container
              orientation="vertical"
              gap="xs"
              style={{ maxHeight: "200px", overflowY: "auto" }}
            >
              {data.connectionHistory && data.connectionHistory.length > 0 ? (
                data.connectionHistory
                  .slice(-10)
                  .reverse()
                  .map((event, index) => (
                    <Container
                      key={index}
                      orientation="vertical"
                      gap="xs"
                      padding="sm"
                      style={{
                        backgroundColor: "var(--color-background-muted)",
                        borderRadius: "4px",
                      }}
                    >
                      <Container
                        orientation="horizontal"
                        justifyContent="space-between"
                        alignItems="center"
                      >
                        <Text size="sm" weight="medium">
                          {formatEventName(event.event)}
                        </Text>
                        <Text size="xs" color="muted">
                          {new Date(event.timestamp).toLocaleString()}
                        </Text>
                      </Container>
                      {event.details &&
                        Object.keys(event.details).length > 0 && (
                          <Text size="xs" color="muted">
                            {event.details.code && event.details.reason
                              ? `Code: ${event.details.code}, Reason: ${event.details.reason}`
                              : event.details.message ||
                                JSON.stringify(event.details)}
                          </Text>
                        )}
                    </Container>
                  ))
              ) : (
                <Text color="muted" size="sm">
                  No connection events yet
                </Text>
              )}
            </Container>
          </Container>
        </Panel>
      </Container>
    </Container>
  );
}
