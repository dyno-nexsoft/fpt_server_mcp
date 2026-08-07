# fpt_server MCP Server

A Model Context Protocol (MCP) server for the `fpt_server` CI/build REST API.
Lets an AI assistant trigger builds, watch job state, and drive the build
queue directly from chat.

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
- The server's public URL may change over time. Update `FPT_SERVER_BASE_URL`
  when it does; there is no way to discover the new URL from inside this MCP
  server.

## Configuration

Create a `.env` file in the project root (or pass via MCP client `env` block):

```env
FPT_SERVER_BASE_URL=https://<fpt-server-host>/api/v1
FPT_SERVER_API_KEY=<secret>
```

## MCP Client Integration

This server communicates via stdio transport.

Every push of a `vX.Y.Z` tag publishes `@dyno-nexsoft/fpt_server_mcp` to GitHub
Packages (see `.github/workflows/publish.yml`). GitHub Packages requires
authentication even for reads, so each person needs a GitHub PAT with
`read:packages` scope and a `.npmrc` pointing the scope at that registry:

```ini
# ~/.npmrc (or a project-local .npmrc)
@dyno-nexsoft:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=<your GitHub PAT with read:packages>
```

Then reference it in the MCP client config without a local checkout:

```json
{
  "mcpServers": {
    "fpt_server": {
      "command": "npx",
      "args": ["-y", "@dyno-nexsoft/fpt_server_mcp"],
      "env": {
        "FPT_SERVER_BASE_URL": "https://<fpt-server-host>/api/v1",
        "FPT_SERVER_API_KEY": "<secret>"
      }
    }
  }
}
```

### Releasing a new version

```bash
npm version patch   # or minor / major — bumps package.json and creates a git tag
git push origin main --tags
```

The tag push triggers the `publish` workflow, which builds, tests, and
publishes the new version. No `NPM_TOKEN` secret is needed — publishing uses
the workflow's built-in `GITHUB_TOKEN`.

## Development

```bash
npm install
npm run build      # Compile TypeScript
npm run dev        # Watch mode
npm test           # Unit tests (Jest)
```

### Project structure

```
src/
├── index.ts               # MCP server entry point
├── fptClient.ts            # Axios client: API key header, selective GET cache
├── tools.ts                # Thin orchestrator
├── utils/
│   ├── mcpResponse.ts       # mcpText · mcpError
│   └── jobFormatter.ts      # Job type · jobToMarkdown · jobsToMarkdown
└── tools/
    ├── metaTool.ts          # fpt_health · fpt_status · fpt_list_actions · fpt_describe_action
    ├── jobTool.ts           # fpt_list_jobs · fpt_get_job · fpt_get_job_log · fpt_cancel_job · fpt_promote_job · fpt_retry_job
    ├── buildTool.ts         # fpt_ci_build · fpt_ci_gen · fpt_ci_replace · fpt_ci_clean
    ├── zentaoTool.ts        # fpt_zentao_report_*
    ├── adminTool.ts         # fpt_admin_apikeys_* · fpt_admin_logs_tail · fpt_cron_run · fpt_hot_reload · fpt_restart
    └── actionTool.ts        # fpt_invoke_action
```
