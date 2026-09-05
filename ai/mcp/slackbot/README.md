# ClickHouse MCP Slack bot

Ask about ClickHouse data in mentions or direct messages and receive optional Vega-Lite charts. This example uses **PydanticAI 2.40.0**, **Slack Bolt 1.30.0**, and **ClickHouse MCP 0.6.0**, with a refreshed uv lockfile. Imports, real PNG rendering, mocked uploads, and error handling passed on 5 September 2026. The live Luna query passed with mocked Slack transport; Slack delivery remains unverified; see [validation](../VALIDATION.md).

Connect your data using [ClickHouse Cloud](https://console.clickhouse.cloud/signUp), including **$300 credits for a 30-day trial**.


## OpenAI configuration

Set `LLM_PROVIDER=openai`, `OPENAI_MODEL=gpt-5.6-luna`, and `OPENAI_API_KEY` before launching. Put these in `.env`. `OPENAI_BASE_URL` optionally selects an OpenAI-compatible endpoint. The Luna path was tested live against ClickHouse 26.8.2.7. Other provider paths retain their configurable models and are separately unverified.


## Configure Slack

Create an app at https://api.slack.com/apps and enable **Socket Mode**. Generate an app-level token with `connections:write` for `SLACK_APP_TOKEN`.

Add bot scopes `app_mentions:read`, `chat:write`, `im:history`, `channels:history`, and `files:write`. For private-channel thread history, add `groups:history`. Enable event subscriptions for `app_mention` and `message.im`. Enable the App Home Messages tab so people can message the bot.

Install the app in your workspace, copy its bot token to `SLACK_BOT_TOKEN`, and invite it to a channel. Review the current [Slack Socket Mode setup](https://docs.slack.dev/tools/bolt-python/concepts/socket-mode/) and [thread history requirements](https://docs.slack.dev/reference/methods/conversations.replies/) for your workspace.

## Run

Follow the [shared setup](../README.md#setup). From this directory, create a local `.env`:

```dotenv
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_APP_TOKEN=xapp-your-app-token
LLM_PROVIDER=openai
OPENAI_API_KEY=your-key
OPENAI_MODEL=gpt-5.6-luna
CLICKHOUSE_HOST=sql-clickhouse.clickhouse.com
CLICKHOUSE_PORT=8443
CLICKHOUSE_USER=demo
CLICKHOUSE_PASSWORD=
CLICKHOUSE_SECURE=true
```

For local ClickHouse or Cloud, replace the ClickHouse values using the shared instructions and load the same fixture.

```sh
uv sync --locked --python 3.13
uv run --locked main.py
```

Mention the bot or send it a DM: “What tables are available?” For the fixture, ask “Show a bar chart of revenue by region from mcp_demo.sales.” Expected revenue: North 250, South 500. Mention the bot again for channel-thread follow-ups; the app retrieves paginated thread history as context.

Charts are rendered locally with vl-convert and uploaded with `files_upload_v2`. Query or upload failures produce a failure response instead of claiming a chart was uploaded. Bot messages and message-change events are ignored.

## Offline checks and cleanup

```sh
uv run --locked ../tests/app_smoke.py slackbot
```

This renders a real PNG but mocks Slack uploads. It sends no Slack messages. Stop with Ctrl-C; remove the Slack app from the workspace when finished and follow [database cleanup](../README.md#cleanup).
