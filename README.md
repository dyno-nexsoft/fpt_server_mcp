# fpt_server MCP Server

A Model Context Protocol (MCP) server for the `fpt_server` CI/build REST API.
Lets an AI assistant trigger builds, watch job state, and drive the build
queue directly from chat.

Written in Dart (`package:dart_mcp`), matching the rest of the org's stack —
this used to be TypeScript; see git history before the v3.0.0 rewrite for
that implementation.

## Features

| Tool                          | Description                                                |
| ------------------------------ | ----------------------------------------------------------- |
| `fpt_health`                  | Liveness probe (no auth)                                   |
| `fpt_status`                  | Queue state, uptime, running/queued jobs                   |
| `fpt_list_actions`            | Catalogue of every REST-exposed action                     |
| `fpt_describe_action`         | Full parameter schema for one action                        |
| `fpt_list_jobs`               | List jobs, newest first, filterable by state                |
| `fpt_get_job`                 | Full detail of one job                                      |
| `fpt_get_job_log`             | Poll a job's build log by byte offset                        |
| `fpt_cancel_job`              | Cancel a job                                                 |
| `fpt_promote_job`             | Promote a queued job into the parallel lane                 |
| `fpt_retry_job`               | Re-invoke the action recorded on a finished job              |
| `fpt_ci_build`                | Friendly alias for the `ci.build` action                     |
| `fpt_ci_gen`                  | Friendly alias for the `ci.gen` action                       |
| `fpt_ci_replace`              | Friendly alias for the `ci.replace` action                   |
| `fpt_ci_clean`                | Friendly alias for the `ci.clean` action (`invokeDangerous`) |
| `fpt_zentao_report_start`     | Start today's Zentao daily report task                       |
| `fpt_zentao_report_finish`    | Finish a Zentao daily report task                            |
| `fpt_zentao_report_close`     | Close a Zentao daily report task                             |
| `fpt_zentao_report_edit`      | Edit a Zentao daily report task                              |
| `fpt_zentao_report_get`       | View a Zentao daily report task                              |
| `fpt_admin_apikeys_list`      | List your API keys                                           |
| `fpt_admin_apikeys_add`       | Create a new API key                                         |
| `fpt_admin_apikeys_remove`    | Delete an API key                                            |
| `fpt_admin_logs_tail`         | Read the last N lines of server.log (`admin` scope)          |
| `fpt_cron_run`                | Run a scheduled job immediately (`invokeDangerous`)          |
| `fpt_hot_reload`              | Pull latest code and hot reload, no restart (`admin` scope)  |
| `fpt_restart`                 | Pull latest code and restart the process (`admin` scope)     |
| `fpt_invoke_action`           | Generic dispatch — reaches any action by name                |

**Design notes:**
- No login step: auth is a static API key sent as `X-API-Key` on every request.
- GET responses are cached only for `/actions` (rarely changes, 5 min TTL);
  job/status endpoints always hit the network so state stays current.
- No SSE tool: an MCP tool call is request/response, not a long-lived stream.
  Real-time log tailing is exposed instead as `fpt_get_job_log`'s
  offset-based polling — call it again with the returned `nextOffset`.
- `fpt_server` is LAN-only, not published to the public internet. This MCP
  server must run somewhere that can reach it directly — e.g. on the same
  host, pointing `FPT_SERVER_BASE_URL` at `http://localhost:8080/api/v1` —
  or over a VPN/LAN connection to it.
- Wire types (`Job`, `Health`, `SystemStatus`, `ActionSchema`, ...) come from
  [`fpt_server_shared`](https://github.com/dyno-nexsoft/fpt_server_shared),
  the same package the backend and dashboard use — this is a third consumer
  of it, not a fourth hand-copied set of models.

## Configuration

Set these as real OS environment variables (not `--dart-define`) — via a
`.env` you source before running, or the MCP client's own `env` block:

```env
FPT_SERVER_BASE_URL=https://<fpt-server-host>/api/v1
FPT_SERVER_API_KEY=<secret>
```

## MCP Client Integration

This server communicates via stdio transport. Requires a local checkout with
`fpt_server_shared` available as a sibling directory (`../fpt_server_shared`)
— the normal case when this repo is checked out as a submodule of the parent
`fpt_server` repo, since that's where both this repo and `fpt_server_shared`
already live side by side.

```json
{
  "mcpServers": {
    "fpt_server": {
      "command": "dart",
      "args": ["run", "/path/to/fpt_server/fpt_server_mcp/bin/fpt_server_mcp.dart"],
      "env": {
        "FPT_SERVER_BASE_URL": "https://<fpt-server-host>/api/v1",
        "FPT_SERVER_API_KEY": "<secret>"
      }
    }
  }
}
```

Or point at a compiled executable (built via `dart compile exe
bin/fpt_server_mcp.dart -o fpt_server_mcp`, or downloaded from a
[release](../../releases)) instead of `dart run`, for faster startup:

```json
{
  "mcpServers": {
    "fpt_server": {
      "command": "/path/to/fpt_server_mcp",
      "env": {
        "FPT_SERVER_BASE_URL": "https://<fpt-server-host>/api/v1",
        "FPT_SERVER_API_KEY": "<secret>"
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
    "fpt_server": {
      "type": "local",
      "command": [
        "dart",
        "run",
        "/path/to/fpt_server/fpt_server_mcp/bin/fpt_server_mcp.dart"
      ],
      "environment": {
        "FPT_SERVER_BASE_URL": "https://<fpt-server-host>/api/v1",
        "FPT_SERVER_API_KEY": "<secret>"
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
dart run bin/fpt_server_mcp.dart   # runs the server directly against stdio
```

### Project structure

```
bin/
└── fpt_server_mcp.dart      # Entry point — connects the server to stdio

lib/src/
├── server.dart               # FptMcpServer: registers every tool group
├── fpt_client.dart           # http client: API key header, selective GET cache
├── job_formatter.dart        # jobToMarkdown · jobsToMarkdown
├── mcp_response.dart         # mcpText
└── tools/
    ├── meta_tool.dart         # fpt_health · fpt_status · fpt_list_actions · fpt_describe_action
    ├── job_tool.dart          # fpt_list_jobs · fpt_get_job · fpt_get_job_log · fpt_cancel_job · fpt_promote_job · fpt_retry_job
    ├── build_tool.dart        # fpt_ci_build · fpt_ci_gen · fpt_ci_replace · fpt_ci_clean
    ├── zentao_tool.dart       # fpt_zentao_report_*
    ├── admin_tool.dart        # fpt_admin_apikeys_* · fpt_admin_logs_tail · fpt_cron_run · fpt_hot_reload · fpt_restart
    └── action_tool.dart       # fpt_invoke_action
```
