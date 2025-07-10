class StockDataMonitor {
  constructor() {
    this.updateInterval = null;
    this.isUpdating = false;
    this.lastData = null;

    this.initializeEventListeners();
    this.startUpdating();
  }

  initializeEventListeners() {
    document
      .getElementById("startBtn")
      .addEventListener("click", () => this.controlAction("start"));
    document
      .getElementById("pauseBtn")
      .addEventListener("click", () => this.controlAction("pause"));
    document
      .getElementById("stopBtn")
      .addEventListener("click", () => this.controlAction("stop"));
    document
      .getElementById("restartBtn")
      .addEventListener("click", () => this.controlAction("restart"));
  }

  async controlAction(action) {
    try {
      const response = await fetch(`/control/${action}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
      });

      const result = await response.json();

      if (result.success) {
        this.showAlert(result.message, "success");
        this.updateData();
      } else {
        this.showAlert("Action failed", "error");
      }
    } catch (error) {
      console.error("Control action failed:", error);
      this.showAlert("Network error", "error");
    }
  }

  async updateData() {
    if (this.isUpdating) return;
    this.isUpdating = true;

    try {
      const response = await fetch("/metrics");
      const data = await response.json();

      this.lastData = data;
      this.updateUI(data);
      this.updateLastUpdatedTime();
    } catch (error) {
      console.error("Failed to fetch data:", error);
      this.showAlert("Failed to fetch data", "error");
    } finally {
      this.isUpdating = false;
    }
  }

  updateUI(data) {
    this.updateStatusBanner(data);
    this.updateMetrics(data);
    this.updateDetails(data);
    this.updateConnectionHistory(data);
  }

  updateStatusBanner(data) {
    const indicator = document.getElementById("statusIndicator");
    const statusMain = document.getElementById("statusMain");
    const statusDetail = document.getElementById("statusDetail");

    indicator.className = "status-indicator";

    if (data.paused) {
      indicator.classList.add("paused");
      statusMain.textContent = "PAUSED";
      statusDetail.textContent = "Data ingestion is paused";
    } else if (data.connected) {
      indicator.classList.add("connected");
      statusMain.textContent = "CONNECTED";
      statusDetail.textContent =
        data.statusMessage || "Active - Receiving data";
    } else {
      indicator.classList.add("disconnected");
      statusMain.textContent = "DISCONNECTED";
      statusDetail.textContent =
        data.statusMessage || "Not connected to data feed";
    }
  }

  updateMetrics(data) {
    document.getElementById("uptime").textContent = this.formatUptime(
      data.uptime
    );
    document.getElementById(
      "totalUptime"
    ).textContent = `Total: ${this.formatUptime(data.totalUptime)}`;

    document.getElementById("tradesInserted").textContent = this.formatNumber(
      data.tradesInserted
    );
    document.getElementById("quotesInserted").textContent = this.formatNumber(
      data.quotesInserted
    );
    document.getElementById("totalRecords").textContent = this.formatNumber(
      data.totalRecordsInserted
    );

    document.getElementById(
      "processedMessages"
    ).textContent = `Processed: ${this.formatNumber(data.processedMessages)}`;
    document.getElementById(
      "memoryUsage"
    ).textContent = `${data.memoryUsageMB} MB`;
    document.getElementById(
      "droppedMessages"
    ).textContent = `Dropped: ${this.formatNumber(data.droppedMessages)}`;

    document.getElementById("queueLength").textContent = data.queueLength;
    document.getElementById(
      "runningInserts"
    ).textContent = `Active inserts: ${data.runningInserts}`;
  }

  updateDetails(data) {
    document.getElementById("tradesBatchSize").textContent =
      data.batchSizes?.trades || 0;
    document.getElementById("quotesBatchSize").textContent =
      data.batchSizes?.quotes || 0;

    const timeSinceMessage = data.timeSinceLastMessage;
    document.getElementById("timeSinceLastMessage").textContent =
      timeSinceMessage < 60
        ? `${Math.round(timeSinceMessage)}s ago`
        : timeSinceMessage < 3600
        ? `${Math.round(timeSinceMessage / 60)}m ago`
        : `${Math.round(timeSinceMessage / 3600)}h ago`;

    document.getElementById(
      "reconnectAttempts"
    ).textContent = `${data.reconnectAttempts} / ${data.maxReconnectAttempts}`;
  }

  updateConnectionHistory(data) {
    const historyContainer = document.getElementById("connectionHistory");

    if (!data.connectionHistory || data.connectionHistory.length === 0) {
      historyContainer.innerHTML =
        '<div class="history-item">No connection events yet</div>';
      return;
    }

    const historyHTML = data.connectionHistory
      .slice(-10)
      .reverse()
      .map((event) => {
        const timestamp = new Date(event.timestamp).toLocaleString();
        const eventClass = this.getEventClass(event.event);

        return `
                    <div class="history-item">
                        <div class="history-timestamp">${timestamp}</div>
                        <div class="history-event ${eventClass}">${this.formatEventName(
          event.event
        )}</div>
                        ${
                          event.details && Object.keys(event.details).length > 0
                            ? `<div class="history-details">${this.formatEventDetails(
                                event.details
                              )}</div>`
                            : ""
                        }
                    </div>
                `;
      })
      .join("");

    historyContainer.innerHTML = historyHTML;
  }

  getEventClass(event) {
    switch (event) {
      case "connected":
        return "connected";
      case "disconnected":
        return "disconnected";
      case "error":
      case "connection_failed":
        return "error";
      default:
        return "";
    }
  }

  formatEventName(event) {
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
  }

  formatEventDetails(details) {
    if (details.code && details.reason) {
      return `Code: ${details.code}, Reason: ${details.reason}`;
    }
    if (details.message) {
      return details.message;
    }
    return JSON.stringify(details);
  }

  formatUptime(seconds) {
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
  }

  formatNumber(num) {
    if (num === undefined || num === null) return "--";

    if (num >= 1000000) {
      return (num / 1000000).toFixed(1) + "M";
    } else if (num >= 1000) {
      return (num / 1000).toFixed(1) + "K";
    } else {
      return num.toLocaleString();
    }
  }

  updateLastUpdatedTime() {
    const now = new Date();
    document.getElementById("lastUpdated").textContent =
      now.toLocaleTimeString();
  }

  showAlert(message, type = "success") {
    const alertContainer = document.getElementById("alertContainer");
    const alertContent = document.getElementById("alertContent");

    alertContent.textContent = message;
    alertContainer.className = `alert ${type}`;
    alertContainer.style.display = "flex";

    setTimeout(() => {
      this.hideAlert();
    }, 5000);
  }

  hideAlert() {
    const alertContainer = document.getElementById("alertContainer");
    alertContainer.style.display = "none";
  }

  startUpdating() {
    this.updateData();
    this.updateInterval = setInterval(() => {
      this.updateData();
    }, 2000);
  }

  stopUpdating() {
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
      this.updateInterval = null;
    }
  }
}

function hideAlert() {
  document.getElementById("alertContainer").style.display = "none";
}

document.addEventListener("DOMContentLoaded", () => {
  window.monitor = new StockDataMonitor();
});

window.addEventListener("beforeunload", () => {
  if (window.monitor) {
    window.monitor.stopUpdating();
  }
});
