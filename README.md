# nexsoft_server MCP Server

A Model Context Protocol (MCP) server for the `nexsoft_server` CI/build REST API.
Lets an AI assistant trigger builds, watch job state, and drive the build
queue directly from chat.

Written in Dart (`package:dart_mcp`), matching the rest of the org's stack —
this used to be TypeScript; see git history before the v3.0.0 rewrite for
that implementation.

## Features

| Tool                          | Description                                                |
| ------------------------------ | ----------------------------------------------------------- |
| `nexsoft_health`                  | Liveness probe (no auth)                                   |
| `nexsoft_status`                  | Queue state, uptime, running/queued jobs                   |
| `nexsoft_list_actions`            | Catalogue of every REST-exposed action                     |
| `nexsoft_describe_action`         | Full parameter schema for one action                        |
| `nexsoft_list_jobs`               | List jobs, newest first, filterable by state                |
| `nexsoft_get_job`                 | Full detail of one job                                      |
| `nexsoft_get_job_log`             | Poll a job's build log by byte offset                        |
| `nexsoft_cancel_job`              | Cancel a job                                                 |
| `nexsoft_promote_job`             | Promote a queued job into the parallel lane                 |
| `nexsoft_retry_job`               | Re-invoke the action recorded on a finished job              |
| `nexsoft_ci_build`                | Friendly alias for the `ci.build` action                     |
| `nexsoft_ci_gen`                  | Friendly alias for the `ci.gen` action                       |
| `nexsoft_ci_replace`              | Friendly alias for the `ci.replace` action                   |
| `nexsoft_ci_clean`                | Friendly alias for the `ci.clean` action (`invokeDangerous`) |
| `nexsoft_zentao_report_start`     | Start today's Zentao daily report task                       |
| `nexsoft_zentao_report_finish`    | Finish a Zentao daily report task                            |
| `nexsoft_zentao_report_close`     | Close a Zentao daily report task                             |
| `nexsoft_zentao_report_edit`      | Edit a Zentao daily report task                              |
| `nexsoft_zentao_report_get`       | View a Zentao daily report task                              |
| `nexsoft_admin_apikeys_list`      | List your API keys                                           |
| `nexsoft_admin_apikeys_add`       | Create a new API key                                         |
| `nexsoft_admin_apikeys_remove`    | Delete an API key                                            |
| `nexsoft_admin_logs_tail`         | Read the last N lines of server.log (`admin` scope)          |
| `nexsoft_cron_run`                | Run a scheduled job immediately (`invokeDangerous`)          |
| `nexsoft_hot_reload`              | Pull latest code and hot reload, no restart (`admin` scope)  |
| `nexsoft_restart`                 | Pull latest code and restart the process (`admin` scope)     |
| `nexsoft_schedule_get`            | Working calendar, days off and every scheduled job with its next run |
| `nexsoft_schedule_set_weekday`    | Make a weekday a working day or not, and set its hours (`admin` scope) |
| `nexsoft_schedule_add_exception`  | Declare a day off or a make-up working day on a date (`admin` scope) |
| `nexsoft_schedule_remove_exception` | Remove a day off or make-up day (`admin` scope)            |
| `nexsoft_schedule_set_job`        | Switch a job on/off, move it, or add a spoken announcement (`admin` scope) |
| `nexsoft_schedule_remove_job`     | Delete a spoken announcement (`admin` scope)                 |
| `nexsoft_limits_get` / `nexsoft_limits_set` | Show / change the admin limits: retention, timeouts, AI settings |
| `nexsoft_ai_provider_get` / `nexsoft_ai_provider_set` | Show / select the AI provider (Gemini or Groq) and failover |
| `nexsoft_invoke_action`           | Generic dispatch — reaches any action by name                |

**Design notes:**
- No login step: auth is a static API key sent as `X-API-Key` on every request.
- GET responses are cached only for `/actions` (rarely changes, 5 min TTL);
  job/status endpoints always hit the network so state stays current.
- No SSE tool: an MCP tool call is request/response, not a long-lived stream.
  Real-time log tailing is exposed instead as `nexsoft_get_job_log`'s
  offset-based polling — call it again with the returned `nextOffset`.
- `nexsoft_server` is LAN-only, not published to the public internet. This MCP
  server must run somewhere that can reach it directly — e.g. on the same
  host, pointing `NEXSOFT_SERVER_BASE_URL` at `http://localhost:8080/api/v1` —
  or over a VPN/LAN connection to it.
- Wire types (`Job`, `Health`, `SystemStatus`, `ActionSchema`, ...) come from
  [`nexsoft_server_shared`](https://github.com/dyno-nexsoft/nexsoft_server_shared),
  the same package the backend and dashboard use — this is a third consumer
  of it, not a fourth hand-copied set of models.

## Configuration

Set these as real OS environment variables (not `--dart-define`) — via a
`.env` you source before running, or the MCP client's own `env` block:

```env
NEXSOFT_SERVER_BASE_URL=https://<nexsoft-server-host>/api/v1
NEXSOFT_SERVER_API_KEY=<secret>
```

## MCP Client Integration

This server communicates via stdio transport. Requires a local checkout with
`nexsoft_server_shared` available as a sibling directory (`../nexsoft_server_shared`)
— the normal case when this repo is checked out as a submodule of the parent
`nexsoft_server` repo, since that's where both this repo and `nexsoft_server_shared`
already live side by side.

```json
{
  "mcpServers": {
    "nexsoft_server": {
      "command": "dart",
      "args": ["run", "/path/to/nexsoft_server/nexsoft_server_mcp/bin/nexsoft_server_mcp.dart"],
      "env": {
        "NEXSOFT_SERVER_BASE_URL": "https://<nexsoft-server-host>/api/v1",
        "NEXSOFT_SERVER_API_KEY": "<secret>"
      }
    }
  }
}
```

Or point at a compiled executable (built via `dart compile exe
bin/nexsoft_server_mcp.dart -o nexsoft_server_mcp`, or downloaded from a
[release](../../releases)) instead of `dart run`, for faster startup:

```json
{
  "mcpServers": {
    "nexsoft_server": {
      "command": "/path/to/nexsoft_server_mcp",
      "env": {
        "NEXSOFT_SERVER_BASE_URL": "https://<nexsoft-server-host>/api/v1",
        "NEXSOFT_SERVER_API_KEY": "<secret>"
      }
    }
  }
}
```

### opencode

[opencode](https://opencode.ai)'s `opencode.jsonc` uses a different shape for
local MCP servers: `type: "local"` is required, `command` is a single array
(the executable and every argument combined, not split into `command`+`args`),
and the env block is called `environment`, not `env`:

```jsonc
{
  "mcp": {
    "nexsoft_server": {
      "type": "local",
      "command": [
        "dart",
        "run",
        "/path/to/nexsoft_server/nexsoft_server_mcp/bin/nexsoft_server_mcp.dart"
      ],
      "environment": {
        "NEXSOFT_SERVER_BASE_URL": "https://<nexsoft-server-host>/api/v1",
        "NEXSOFT_SERVER_API_KEY": "<secret>"
      }
    }
  }
}
```

## Development

```bash
dart pub get
dart analyze
dart test
dart run bin/nexsoft_server_mcp.dart   # runs the server directly against stdio
```

### Project structure

```
bin/
└── nexsoft_server_mcp.dart      # Entry point — connects the server to stdio

lib/src/
├── server.dart               # NexsoftMcpServer: registers every tool group
├── nexsoft_client.dart           # http client: API key header, selective GET cache
├── job_formatter.dart        # jobToMarkdown · jobsToMarkdown
├── mcp_response.dart         # mcpText
└── tools/
    ├── meta_tool.dart         # nexsoft_health · nexsoft_status · nexsoft_list_actions · nexsoft_describe_action
    ├── job_tool.dart          # nexsoft_list_jobs · nexsoft_get_job · nexsoft_get_job_log · nexsoft_cancel_job · nexsoft_promote_job · nexsoft_retry_job
    ├── build_tool.dart        # nexsoft_ci_build · nexsoft_ci_gen · nexsoft_ci_replace · nexsoft_ci_clean
    ├── zentao_tool.dart       # nexsoft_zentao_report_*
    ├── admin_tool.dart        # nexsoft_admin_apikeys_* · nexsoft_admin_logs_tail · nexsoft_cron_run · nexsoft_hot_reload · nexsoft_restart
    ├── config_tool.dart       # nexsoft_schedule_* · nexsoft_limits_* (read-modify-write over schedule.* and limits.*)
    └── action_tool.dart       # nexsoft_invoke_action
```
