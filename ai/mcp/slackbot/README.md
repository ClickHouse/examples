# Slack ClickHouse AI Bot

This bot allows you to ask questions about your ClickHouse data directly from Slack, using natural language. It uses the ClickHouse MCP server and PydanticAI.

---

## Features
- **Ask in Slack:** Mention the bot in a channel, reply to a thread, or DM the bot with your question.
- **AI-Powered:** Uses Anthropic Claude (via Pydantic AI SDK) to interpret questions and generate SQL.
- **ClickHouse Integration:** Queries your ClickHouse database using MCP.
- **Thread Awareness:** When replying in a thread, the bot uses the full conversation history as context.

---

## Configuration

### Dependencies

1. Python `uv`
2. A Slack workspace

### Configure Slack

1. **Create a Slack App**
    - Go to [https://api.slack.com/apps](https://api.slack.com/apps) and click **"Create New App"**
    - Choose **"From scratch"** and give your app a name
    - Select your Slack workspace

2. **Install the app to your workspace**
3. **Configure Slack App Settings**
    - Go to **App Home**
        - Under "Show Tabs" → "Messages Tab": Enable **Allow users to send Slash commands and messages from the messages tab**
    - Go to **Socket Mode**
        - Enable **Socket Mode**
        - Note down the **Socket Mode Handler** for the environment variable `SLACK_APP_TOKEN`
    - Go to **OAuth & Permissions**
        - Add the following **Bot Token Scopes**:
            - `app_mentions:read`
            - `assistant:write`
            - `chat:write`
            - `im:history`
            - `im:read`
            - `im:write`
            - `channels:history`
        - Install the app to your workspace and note down the **Bot User OAuth Token** for the environment variable `SLACK_BOT_TOKEN`.
    - Go to **Event Subscriptions**
        - Enable **Events**
        - Under **Subscribe to bot events**, add:
            - `app_mention`
            - `assistant_thread_started`
            - `message:im`
        - Save Changes
4. **Add the app to a workspace channel**

### Environment Variables (`.env`)
Create a `.env` file in the project root with the following:

```env
SLACK_BOT_TOKEN=your-slack-bot-token
SLACK_APP_TOKEN=your-slack-app-level-token
ANTHROPIC_API_KEY=your-anthropic-api-key
CLICKHOUSE_HOST=sql-clickhouse.clickhouse.com
CLICKHOUSE_PORT=8443
CLICKHOUSE_USER=demo
CLICKHOUSE_PASSWORD=
CLICKHOUSE_SECURE=true
```

You can adapt the ClickHouse variables to use your own ClickHouse server. If you leave them as-is, they will connect to the [public ClickHouse playground](https://sql.clickhouse.com/).

---

## Usage

1. **Start the bot:**
   ```sh
   uv run main.py
   ```
2. **In Slack:**
   - Mention the bot in a channel: `@yourbot Who are the top contributors to the ClickHouse git repo?`
   - Reply to the thread with a mention: `@yourbot how many contributions did these users make last week?`
   - DM the bot: `Show me all tables in the demo database.`

The bot will reply in the thread, using all previous thread messages as context if applicable.

---

**Thread Context:**
When replying in a thread, the bot loads all previous messages (except the current one) and includes them as context for the AI.

**Tool Usage:**
The bot uses only the tools available via MCP (e.g., schema discovery, SQL execution) and will always show the SQL used and a summary of how the answer was found.

---

## Tools used
- [Pydantic AI SDK](https://github.com/pydantic/pydantic-ai)
- [Slack Bolt](https://slack.dev/bolt-python/)
- [ClickHouse](https://clickhouse.com/)
- [ClickHouse MCP](https://github.com/ClickHouse/mcp-clickhouse)
