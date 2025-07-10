require("dotenv").config();
const express = require("express");
const WebSocket = require("ws");
const { createClient } = require("@clickhouse/client");
const { ClickHouseError } = require("@clickhouse/client-common");
const { Kafka } = require("kafkajs");
const path = require("path");

class StockDataIngester {
  constructor() {
    this.app = express();
    this.port = process.env.PORT || 34567;

    this.ws = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 10;
    this.reconnectDelay = 5000;
    this.isConnected = false;
    this.isShuttingDown = false;
    this.isPaused = false;
    this.shouldReconnect = true;

    this.client = createClient({
      host: process.env.CLICKHOUSE_HOST,
      username: process.env.CLICKHOUSE_USERNAME,
      password: process.env.CLICKHOUSE_PASSWORD,
      max_open_connections: 50,
      clickhouse_settings: {
        async_insert: 1,
        wait_for_async_insert: 0,
        async_insert_max_data_size: "5000000",
        async_insert_busy_timeout_ms: 2000,
      },
    });

    if (process.env.KAFKA_ENABLED === 'true') {
      this.kafka = new Kafka({
        clientId: "stock-data-ingester",
        brokers: [process.env.KAFKA_BROKER],
        ssl: true,
        sasl: {
          mechanism: "plain",
          username: process.env.KAFKA_USERNAME,
          password: process.env.KAFKA_PASSWORD,
        },
        retry: {
          initialRetryTime: 100,
          retries: 8,
        },
      });
      this.kafkaProducer = null;
      this.kafkaConnected = false;
      this.kafkaMessagesProduced = 0;
      this.kafkaErrors = 0;    this.kafkaConnected = false;
      this.kafkaMessagesProduced = 0;
      this.kafkaErrors = 0;
      this.initializeKafka();
    }

    this.tradesBatch = [];
    this.quotesBatch = [];
    this.maxBatchSize = 1000;
    this.maxMemoryUsage = 2 * 1024 * 1024 * 1024;
    this.batchTimeout = 2000;
    this.runningInserts = 0;
    this.maxConcurrentInserts = 50;
    this.insertQueue = [];
    this.droppedMessages = 0;
    this.processedMessages = 0;

    this.tradesInserted = 0;
    this.quotesInserted = 0;
    this.connectionStartTime = null;
    this.lastDisconnectTime = null;
    this.totalUptime = 0;
    this.connectionHistory = [];
    this.statusMessage = "Initializing...";

    this.insertHistory = [];
    this.maxHistoryAge = 60000;

    this.batchTimer = null;
    this.healthCheckInterval = null;
    this.lastMessageTime = Date.now();

    this.authMsg = JSON.stringify({
      action: "auth",
      params: process.env.POLYGON_API_KEY,
    });

    this.tradesSubscriptionMsg = JSON.stringify({
      action: "subscribe",
      params: "T.*",
    });

    this.quotesSubscriptionMsg = JSON.stringify({
      action: "subscribe",
      params: "Q.*",
    });

    this.setupExpress();
    this.initializeTimers();
    this.setupGracefulShutdown();

  }

  async initializeKafka() {
    try {
      console.log("Initializing Kafka producer...");
      this.kafkaProducer = this.kafka.producer({
        allowAutoTopicCreation: false,
        transactionTimeout: 30000,
      });

      await this.kafkaProducer.connect();
      this.kafkaConnected = true;
      console.log("Kafka producer connected successfully");
    } catch (error) {
      console.error("Failed to initialize Kafka producer:", error);
      this.kafkaConnected = false;
      this.kafkaErrors++;
    }
  }

  setupExpress() {
    this.app.use(express.json());
    this.app.use(express.static(path.join(__dirname, "public")));

    this.app.get("/health", (req, res) => {
      res.json(this.getDetailedStatus());
    });

    this.app.post("/control/start", (req, res) => {
      this.startIngestion();
      res.json({ success: true, message: "Ingestion started" });
    });

    this.app.post("/control/stop", (req, res) => {
      this.stopIngestion();
      res.json({ success: true, message: "Ingestion stopped" });
    });

    this.app.post("/control/pause", (req, res) => {
      this.pauseIngestion();
      res.json({ success: true, message: "Ingestion paused" });
    });

    this.app.post("/control/restart", (req, res) => {
      this.restartIngestion();
      res.json({ success: true, message: "Ingestion restarting" });
    });

    this.app.get("/metrics", (req, res) => {
      res.json(this.getDetailedStatus());
    });

    // Kafka control endpoints
    this.app.post("/control/kafka/reconnect", async (req, res) => {
      try {
        await this.reconnectKafka();
        res.json({
          success: true,
          message: "Kafka reconnection attempted",
          connected: this.kafkaConnected,
        });
      } catch (error) {
        res.status(500).json({
          success: false,
          message: "Kafka reconnection failed",
          error: error.message,
        });
      }
    });

    this.app.post("/control/kafka/test", async (req, res) => {
      if (!this.kafkaConnected || !this.kafkaProducer) {
        return res.status(503).json({
          success: false,
          message: "Kafka not connected",
        });
      }

      // Send test message to Kafka
      try {
        await this.sendToKafka("stocks-trades", {
          timestamp: Date.now(),
          test: true,
          message: "Test message from stock data ingester",
        });

        res.json({
          success: true,
          message: "Test message sent to Kafka successfully",
        });
      } catch (error) {
        res.status(500).json({
          success: false,
          message: "Failed to send test message to Kafka",
          error: error.message,
        });
      }
    });

    this.app.get("/control/kafka/status", (req, res) => {
      res.json({
        connected: this.kafkaConnected,
        messagesProduced: this.kafkaMessagesProduced,
        errors: this.kafkaErrors,
        brokers: [process.env.KAFKA_BROKER],
        topics: ["stocks-trades", "stocks-quotes"],
      });
    });

    this.setupStockUIRoutes();
  }

  setupStockUIRoutes() {
    this.app.get("/stocks", (req, res) => {
      res.sendFile(path.join(__dirname, "frontend/out", "index.html"));
    });

    this.app.get("/admin", (req, res) => {
      res.sendFile(path.join(__dirname, "frontend/out", "admin", "index.html"));
    });

    this.app.use(
      "/stocks",
      express.static(path.join(__dirname, "frontend/out"))
    );

    this.app.use(
      "/admin",
      express.static(path.join(__dirname, "frontend/out"))
    );
  }

  getDetailedStatus() {
    const now = Date.now();
    const currentUptime = this.connectionStartTime
      ? (now - this.connectionStartTime) / 1000
      : 0;
    const timeSinceLastDisconnect = this.lastDisconnectTime
      ? (now - this.lastDisconnectTime) / 1000
      : null;

    const throughput = this.calculateThroughput();

    return {
      status: this.isPaused
        ? "paused"
        : this.isConnected
        ? "connected"
        : "disconnected",
      connected: this.isConnected,
      paused: this.isPaused,
      uptime: currentUptime,
      totalUptime: this.totalUptime + currentUptime,
      timeSinceLastDisconnect,
      runningInserts: this.runningInserts,
      queueLength: this.insertQueue.length,
      memoryUsage: this.getMemoryUsage(),
      memoryUsageMB: Math.round(this.getMemoryUsage() / 1024 / 1024),
      processedMessages: this.processedMessages,
      droppedMessages: this.droppedMessages,
      tradesInserted: this.tradesInserted,
      quotesInserted: this.quotesInserted,
      totalRecordsInserted: this.tradesInserted + this.quotesInserted,
      batchSizes: {
        trades: this.tradesBatch.length,
        quotes: this.quotesBatch.length,
      },
      throughput: throughput,
      reconnectAttempts: this.reconnectAttempts,
      maxReconnectAttempts: this.maxReconnectAttempts,
      statusMessage: this.statusMessage,
      connectionHistory: this.connectionHistory.slice(-10),
      lastMessageTime: this.lastMessageTime,
      timeSinceLastMessage: (now - this.lastMessageTime) / 1000,
      kafka: {
        connected: this.kafkaConnected,
        messagesProduced: this.kafkaMessagesProduced,
        errors: this.kafkaErrors,
      },
    };
  }

  calculateThroughput() {
    const now = Date.now();
    const oneMinuteAgo = now - this.maxHistoryAge;

    const recentInserts = this.insertHistory.filter(
      (insert) => insert.timestamp > oneMinuteAgo
    );

    const trades = recentInserts.filter((insert) => insert.table === "trades");
    const quotes = recentInserts.filter((insert) => insert.table === "quotes");

    const tradesPerSecond =
      trades.reduce((sum, insert) => sum + insert.count, 0) / 60;
    const quotesPerSecond =
      quotes.reduce((sum, insert) => sum + insert.count, 0) / 60;
    const totalPerSecond = tradesPerSecond + quotesPerSecond;

    return {
      tradesPerSecond: Math.round(tradesPerSecond * 10) / 10,
      quotesPerSecond: Math.round(quotesPerSecond * 10) / 10,
      totalPerSecond: Math.round(totalPerSecond * 10) / 10,
    };
  }

  startIngestion() {
    this.shouldReconnect = true;
    this.isPaused = false;
    this.statusMessage = "Starting ingestion...";
    if (!this.isConnected) {
      this.connectWebSocket();
    }
  }

  stopIngestion() {
    this.shouldReconnect = false;
    this.isPaused = false;
    this.statusMessage = "Stopping ingestion...";
    if (this.ws) {
      this.ws.close();
    }
    this.isConnected = false;
  }

  pauseIngestion() {
    this.isPaused = true;
    this.statusMessage = "Ingestion paused";
  }

  restartIngestion() {
    this.statusMessage = "Restarting ingestion...";
    this.stopIngestion();
    setTimeout(() => {
      this.startIngestion();
    }, 1000);
  }

  logConnectionEvent(event, details = {}) {
    const timestamp = new Date().toISOString();
    this.connectionHistory.push({
      timestamp,
      event,
      details,
      reconnectAttempts: this.reconnectAttempts,
    });

    if (this.connectionHistory.length > 50) {
      this.connectionHistory = this.connectionHistory.slice(-50);
    }
  }

  initializeTimers() {
    this.batchTimer = setInterval(() => {
      if (!this.isPaused) {
        this.flushBatches();
      }
    }, this.batchTimeout);

    this.healthCheckInterval = setInterval(() => {
      this.performHealthCheck();
    }, 30000);
  }

  getMemoryUsage() {
    const usage = process.memoryUsage();
    return usage.heapUsed;
  }

  isMemoryPressure() {
    return this.getMemoryUsage() > this.maxMemoryUsage;
  }

  async connectWebSocket() {
    if (this.isShuttingDown || !this.shouldReconnect) return;

    console.log(
      `Attempting WebSocket connection (attempt ${this.reconnectAttempts + 1})`
    );
    this.statusMessage = `Connecting... (attempt ${
      this.reconnectAttempts + 1
    })`;

    try {
      this.ws = new WebSocket("wss://socket.polygon.io/stocks");

      this.ws.on("open", () => {
        console.log("WebSocket connected");
        this.isConnected = true;
        this.reconnectAttempts = 0;
        this.lastMessageTime = Date.now();
        this.connectionStartTime = Date.now();
        this.statusMessage = "Connected - Authenticating...";
        this.logConnectionEvent("connected");
        this.ws.send(this.authMsg);
      });

      this.ws.on("message", (data) => {
        if (!this.isPaused) {
          this.handleMessage(data);
        }
      });

      this.ws.on("close", (code, reason) => {
        console.log(`WebSocket closed: ${code} ${reason}`);
        this.handleDisconnection();
        this.logConnectionEvent("disconnected", {
          code,
          reason: reason.toString(),
        });
      });

      this.ws.on("error", (error) => {
        console.error("WebSocket error:", error);
        this.handleDisconnection();
        this.logConnectionEvent("error", { message: error.message });
      });

      this.ws.on("ping", () => {
        this.ws.pong();
      });
    } catch (error) {
      console.error("Failed to create WebSocket:", error);
      this.handleDisconnection();
      this.logConnectionEvent("connection_failed", { message: error.message });
    }
  }

  handleDisconnection() {
    if (this.connectionStartTime) {
      this.totalUptime += (Date.now() - this.connectionStartTime) / 1000;
      this.connectionStartTime = null;
    }

    this.isConnected = false;
    this.lastDisconnectTime = Date.now();

    if (this.shouldReconnect && !this.isShuttingDown) {
      this.statusMessage = "Disconnected - Will reconnect...";
      this.scheduleReconnect();
    } else {
      this.statusMessage = "Disconnected";
    }
  }

  scheduleReconnect() {
    if (this.isShuttingDown || !this.shouldReconnect) return;

    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error(
        "Max reconnection attempts reached. Stopping reconnection."
      );
      this.statusMessage = "Max reconnection attempts reached";
      this.shouldReconnect = false;
      return;
    }

    this.reconnectAttempts++;
    const delay = Math.min(
      this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1),
      60000
    );

    console.log(`Scheduling reconnection in ${delay}ms`);
    this.statusMessage = `Reconnecting in ${Math.round(delay / 1000)}s...`;

    setTimeout(() => {
      if (this.shouldReconnect && !this.isShuttingDown) {
        this.connectWebSocket();
      }
    }, delay);
  }

  handleMessage(data) {
    try {
      this.lastMessageTime = Date.now();
      const payload = JSON.parse(data);

      if (payload[0] && payload[0].ev === "status") {
        this.handleStatusMessage(payload[0]);
        return;
      }

      const originalMessageLength = payload.length;

      if (this.isMemoryPressure()) {
        this.droppedMessages++;
        console.warn(
          `Memory pressure: dropped message with ${originalMessageLength} events. Total dropped: ${this.droppedMessages}`
        );
        return;
      }

      const trades = payload
        .filter((row) => row.ev === "T")
        .map(({ ev, ...fields }) => fields);

      const quotes = payload
        .filter((row) => row.ev === "Q")
        .map(({ ev, ...fields }) => fields);

      const otherEvents = payload.filter(
        (row) => row.ev !== "T" && row.ev !== "Q" && row.ev !== "status"
      );

      if (otherEvents.length > 0) {
        console.log(
          `Received ${otherEvents.length} non-T/Q events:`,
          otherEvents.map((e) => e.ev).join(", ")
        );
      }

      this.addToBatch(trades, "trades");
      this.addToBatch(quotes, "quotes");
      this.processedMessages++;

      if (this.processedMessages % 10000 === 0) {
        console.log(
          `Processing stats: ${this.processedMessages} messages, ${
            this.tradesInserted + this.quotesInserted
          } records total`
        );
      }
    } catch (error) {
      console.error("Error handling message:", error);
      console.error("Message data:", data.toString().substring(0, 200));
    }
  }

  handleStatusMessage(status) {
    if (status.status === "connected") {
      console.log("Connection Initialized!");
      this.statusMessage = "Connection Initialized!";
    } else if (status.status === "auth_success") {
      console.log("Successfully Authenticated. Subscribing to tickers...");
      this.statusMessage = "Authenticated - Subscribing to data feeds...";
      this.ws.send(this.tradesSubscriptionMsg);
      this.ws.send(this.quotesSubscriptionMsg);
      this.statusMessage = "Active - Receiving data";
    } else {
      console.log("Status:", status);
      this.statusMessage = `Status: ${status.status}`;
    }
  }

  addToBatch(rows, type) {
    if (rows.length === 0) return;

    const batch = type === "trades" ? this.tradesBatch : this.quotesBatch;
    batch.push(...rows);

    if (batch.length >= this.maxBatchSize) {
      this.flushBatch(type);
    }
  }

  flushBatches() {
    this.flushBatch("trades");
    this.flushBatch("quotes");
  }

  flushBatch(type) {
    const batch = type === "trades" ? this.tradesBatch : this.quotesBatch;

    if (batch.length === 0) return;

    const dataToInsert = [...batch];
    if (type === "trades") {
      this.tradesBatch = [];
    } else {
      this.quotesBatch = [];
    }

    this.queueInsert(dataToInsert, type);
  }

  queueInsert(data, table) {
    if (this.runningInserts >= this.maxConcurrentInserts) {
      this.insertQueue.push({ data, table });
      if (this.insertQueue.length > 100) {
        const dropped = this.insertQueue.shift();
        this.droppedMessages += dropped.data.length;
      }
      return;
    }

    this.executeInsert(data, table);
  }

  async executeInsert(data, table) {
    this.runningInserts++;

    try {
      // Write to ClickHouse
      await this.client.insert({
        table: table,
        values: data,
        format: "JSONEachRow",
      });

      const now = Date.now();
      this.insertHistory.push({
        timestamp: now,
        table: table,
        count: data.length,
      });

      this.cleanupInsertHistory();

      if (table === "trades") {
        this.tradesInserted += data.length;
      } else {
        this.quotesInserted += data.length;
      }

      console.info(
        `Inserted ${data.length} ${table} records to ClickHouse successfully`
      );

      // Send to Kafka only if enabled and connected
      if (process.env.KAFKA_ENABLED === 'true') {
        if (this.kafkaConnected && this.kafkaProducer) {
          await this.sendToKafka(kafkaTopic, data);
        } else {
          console.debug(
            `Kafka not connected, skipping Kafka write for ${data.length} ${table} records`
          );
        }
      }
      
    } catch (error) {
      console.error(`Insert failed for ${table}:`, error);

      if (error instanceof ClickHouseError) {
        console.error(`ClickHouse error code: ${error.code}`);
      }
    } finally {
      this.runningInserts--;
      this.processQueue();
    }
  }

  cleanupInsertHistory() {
    const now = Date.now();
    const cutoff = now - this.maxHistoryAge;
    this.insertHistory = this.insertHistory.filter(
      (insert) => insert.timestamp > cutoff
    );
  }

  processQueue() {
    if (
      this.insertQueue.length > 0 &&
      this.runningInserts < this.maxConcurrentInserts
    ) {
      const { data, table } = this.insertQueue.shift();
      this.executeInsert(data, table);
    }
  }

  async reconnectKafka() {
    if (this.kafkaConnected || this.isShuttingDown) return;

    try {
      console.log("Attempting Kafka reconnection...");
      await this.disconnectKafka();
      await this.connectKafka();
      console.log("Kafka producer reconnected successfully");
    } catch (error) {
      console.error("Kafka reconnection failed:", error);
      this.kafkaConnected = false;
      this.kafkaErrors++;
    }
  }


  async connectKafka() {
    if (!this.kafka) {
      throw new Error("Kafka is not initialized");
    }
    
    this.kafkaProducer = this.kafka.producer({
      allowAutoTopicCreation: false,
      transactionTimeout: 30000,
    });
    await this.kafkaProducer.connect();
    this.kafkaConnected = true;
  }

  async disconnectKafka() {
    if (this.kafkaProducer) {
      await this.kafkaProducer.disconnect();
      this.kafkaProducer = null;
    }
    this.kafkaConnected = false;
  }

  async sendToKafka(topic, data) {

    try {
      console.log("send to Kafka")
      const messages = Array.isArray(data) 
        ? data.map(row => ({
            value: JSON.stringify(row),
            timestamp: String(Date.now())
          }))
        : [{
            value: JSON.stringify(data),
            timestamp: String(Date.now())
          }];

      await this.kafkaProducer.send({
        topic,
        messages,
      });

      this.kafkaMessagesProduced += Array.isArray(data) ? data.length : 1;
      console.log(`Sent ${Array.isArray(data) ? data.length : 1} records to Kafka topic: ${topic}`);
    } catch (error) {
      console.error(`Failed to send message to Kafka topic ${topic}:`, error);
      this.kafkaErrors++;
      return;
    }
  }

  performHealthCheck() {
    const now = Date.now();
    const timeSinceLastMessage = now - this.lastMessageTime;

    console.log(
      `Health check - Running inserts: ${this.runningInserts}, Queue: ${
        this.insertQueue.length
      }, Memory: ${Math.round(
        this.getMemoryUsage() / 1024 / 1024
      )}MB, Processed: ${this.processedMessages}, Dropped: ${
        this.droppedMessages
      }, Kafka Connected: ${this.kafkaConnected}, Kafka Messages: ${
        this.kafkaMessagesProduced
      }, Kafka Errors: ${this.kafkaErrors}`
    );

    if (timeSinceLastMessage > 60000 && this.isConnected && !this.isPaused) {
      console.warn(
        "No messages received for 60 seconds, connection may be stale"
      );
      if (this.ws) {
        this.ws.close();
      }
    }

    if (this.isMemoryPressure()) {
      console.warn("Memory pressure detected, forcing batch flush");
      this.flushBatches();
    }

    if (!this.kafkaConnected && !this.isShuttingDown) {
      console.warn("Kafka disconnected, attempting reconnection...");
      this.reconnectKafka();
    }
  }

  setupGracefulShutdown() {
    const shutdown = () => {
      console.log("Received shutdown signal");
      this.gracefulShutdown();
    };

    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
    process.on("uncaughtException", (error) => {
      console.error("Uncaught exception:", error);
      this.gracefulShutdown();
    });
    process.on("unhandledRejection", (reason, promise) => {
      console.error("Unhandled rejection at:", promise, "reason:", reason);
    });
  }

  async gracefulShutdown() {
    if (this.isShuttingDown) return;
    this.isShuttingDown = true;

    console.log("Starting graceful shutdown...");

    if (this.batchTimer) {
      clearInterval(this.batchTimer);
    }
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval);
    }

    if (this.ws) {
      this.ws.close();
    }

    this.flushBatches();

    const maxWaitTime = 30000;
    const startTime = Date.now();

    while (this.runningInserts > 0 && Date.now() - startTime < maxWaitTime) {
      console.log(
        `Waiting for ${this.runningInserts} running inserts to complete...`
      );
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    try {
      await this.client.close();
      console.log("ClickHouse client closed");
    } catch (error) {
      console.error("Error closing ClickHouse client:", error);
    }

    // Disconnect Kafka producer
    if (this.kafkaProducer && this.kafkaConnected) {
      try {
        await this.kafkaProducer.disconnect();
        console.log("Kafka producer disconnected");
      } catch (error) {
        console.error("Error disconnecting Kafka producer:", error);
      }
    }

    console.log(
      `Shutdown complete. Processed: ${this.processedMessages}, Dropped: ${this.droppedMessages}, Kafka Messages: ${this.kafkaMessagesProduced}, Kafka Errors: ${this.kafkaErrors}`
    );
    process.exit(0);
  }

  start() {
    this.connectWebSocket();

    this.app.listen(this.port, () => {
      console.log(`Stock data ingester running on port ${this.port}`);
      console.log(
        `Monitoring UI available at http://localhost:${this.port}/admin`
      );
    });
  }
}

const ingester = new StockDataIngester();
ingester.start();
