# Stock Data Demo Platform

A unified, high-throughput stock data demo platform that combines real-time data ingestion with advanced visualization capabilities. This integrated system handles WebSocket data from Polygon.io, stores it in ClickHouse, and provides both administrative controls and sophisticated stock data visualization.

## **Getting Started**

### **Prerequisites**

- Node.js 18+
- Access to ClickHouse cluster
- Polygon.io API credentials

### **Installation & Startup**

```bash
# Install all dependencies (both backend and frontend)
npm install

# Start the integrated platform
npm start

# For development with hot reloading
npm run dev
```

### **Access Points**

- **Landing Page**: `http://localhost:34567/`
- **Stock Charts UI**: `http://localhost:34567/stocks` _(live candlestick charts)_
- **Admin Controls**: `http://localhost:34567/admin`
- **Health API**: `http://localhost:34567/health`
- **Metrics API**: `http://localhost:34567/metrics`

## **Application Structure**

```
stock-data/
├── app.js                 # Main Express server (ingestion + routing)
├── package.json           # Combined dependencies
├── public/                # Static assets and admin UI
│   ├── index.html         # Unified landing page
│   ├── admin.html         # Ingestion monitoring UI
│   ├── styles.css         # Admin UI styles
│   └── app.js            # Admin UI JavaScript
├── frontend/              # Next.js stock visualization app
│   ├── src/
│   │   ├── components/    # Stock UI components
│   │   │   ├── liveDataTable.tsx
│   │   │   └── liveStockChart.tsx
│   │   ├── queryHandlers/ # ClickHouse query logic
│   │   ├── types/         # TypeScript definitions
│   │   └── app/          # Next.js app structure
│   ├── next.config.mjs    # Next.js configuration
│   └── tsconfig.json      # TypeScript configuration
└── README.md             # This documentation
```

## **Configuration**

### **Environment Variables (.env)**

The application uses several environment variables to configure its behavior. Create a `.env` file in the root directory with the following variables:

```env
# ClickHouse Configuration (Writer)
CLICKHOUSE_HOST=https://your-clickhouse-host:8443
CLICKHOUSE_USERNAME=your_username
CLICKHOUSE_PASSWORD=your_password

# ClickHouse Configuration (Frontend - Reader)
NEXT_PUBLIC_CLICKHOUSE_HOST=https://your-clickhouse-host:8443
NEXT_PUBLIC_CLICKHOUSE_USERNAME=your_username
NEXT_PUBLIC_CLICKHOUSE_PASSWORD=your_password

# Confluent Cloud Kafka Configuration
KAFKA_BROKER=your-kafka-broker:9092
KAFKA_USERNAME=your_kafka_username
KAFKA_PASSWORD=your_kafka_password
KAFKA_ENABLED=false  # Set to 'true' to enable Kafka integration

# Polygon.io API
POLYGON_API_KEY=your_polygon_api_key
```

### **Application Settings**

Key configurable parameters in the `StockDataIngester` class:

```javascript
this.maxBatchSize = 1000; // Records per batch
this.maxMemoryUsage = 100 * 1024 * 1024; // 100MB memory limit
this.batchTimeout = 5000; // 5 second flush interval
this.maxConcurrentInserts = 10; // Max parallel ClickHouse inserts
this.maxReconnectAttempts = 10; // WebSocket reconnection attempts
```

## **Platform Capabilities**

### **Data Ingestion Service**

- **Throughput**: 100,000+ messages per second
- **Memory Management**: Auto-managed with 100MB default limit
- **Latency**: Sub-second batch processing
- **Availability**: Automatic recovery from most failure scenarios
- **Data Types**: Real-time trades and quotes from all US equities

### **Visualization Frontend**

- **Real-time Updates**: Live data refreshes every 100ms
- **Interactive Charts**: Candlestick charts with volume indicators
- **Time Window Selection**: 4 different aggregation periods (5min to 1day) with smart refresh rates
- **Chart Performance**: Optimized refresh intervals from 500ms to 60s based on time window
- **Data Quality**: Direct ClickHouse integration for minimal latency
- **UI Framework**: Modern React with ClickHouse UI components

### **Administrative Interface**

- **Live Monitoring**: Real-time connection status and throughput metrics
- **Control Panel**: Start, stop, pause, and restart data ingestion
- **Performance Tracking**: Memory usage, queue lengths, processing rates
- **Connection History**: Detailed logs of connection events and failures

## **Integration Architecture**

### **Data Flow**

1. **WebSocket Ingestion** → Polygon.io real-time feeds
2. **Data Processing** → Filtering, transformation, and batching
3. **Database Storage** → ClickHouse with batch inserts
4. **UI Data Access** → Direct ClickHouse queries from frontend
5. **Administrative Monitoring** → Express API endpoints

### **Technology Stack**

- **Backend**: Node.js + Express (JavaScript)
- **Frontend**: Next.js + React (TypeScript)
- **Database**: ClickHouse 
- **UI Components**: ClickHouse UI + Custom Components
- **Charts**: Chart.js with financial data extensions and real-time streaming
- **Time Windows**: Multiple aggregation periods (1s, 1m, 2m, 1h buckets) with adaptive refresh rates
- **Real-time**: WebSocket connections + polling

## **Control API**

```bash
# Pause data ingestion
curl -X POST http://localhost:34567/control/pause

# Resume data ingestion
curl -X POST http://localhost:34567/control/start

# Stop ingestion completely
curl -X POST http://localhost:34567/control/stop

# Restart with clean reconnection
curl -X POST http://localhost:34567/control/restart
```

## **Development**

### **Frontend Development**

```bash
# Build frontend for production
npm run frontend:build

# Run frontend in development mode
npm run frontend:dev

# Run only the backend
npm run backend
```
