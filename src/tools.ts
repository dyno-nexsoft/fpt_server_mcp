/**
 * tools.ts — Public surface of the fpt_server MCP tool layer.
 *
 * This file is intentionally thin: it owns the shared FptServerClient
 * singleton and delegates tool registration to focused per-tool modules.
 *
 * To add a new tool: create `src/tools/<name>Tool.ts` and call its
 * register function here — no existing files need to be modified.
 */

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { FptServerClient } from './fptClient.js';
import { registerMetaTools } from './tools/metaTool.js';
import { registerJobTools } from './tools/jobTool.js';
import { registerBuildTools } from './tools/buildTool.js';
import { registerActionTools } from './tools/actionTool.js';
import { registerGitlabTools } from './tools/gitlabTool.js';
import { registerZentaoTools } from './tools/zentaoTool.js';
import { registerAttendanceTools } from './tools/attendanceTool.js';
import { registerAdminTools } from './tools/adminTool.js';

const client = new FptServerClient();

/**
 * Registers all fpt_server MCP tools on the provided server instance.
 *
 * Available tools:
 * - `fpt_health`                 — Liveness probe, no auth.
 * - `fpt_status`                 — Queue state and environment.
 * - `fpt_list_actions`           — Catalogue of every REST-exposed action.
 * - `fpt_describe_action`        — One action's full parameter schema.
 * - `fpt_list_jobs`              — List jobs, newest first, filterable by state.
 * - `fpt_get_job`                — Full detail of one job.
 * - `fpt_get_job_log`            — Poll a job's build log by offset.
 * - `fpt_cancel_job`             — Cancel a job.
 * - `fpt_promote_job`            — Promote a queued job into the parallel lane.
 * - `fpt_retry_job`              — Re-invoke the action recorded on a finished job.
 * - `fpt_trigger_build`          — Friendly alias for the ci.build action.
 * - `fpt_ci_gen`                 — Friendly alias for the ci.gen action.
 * - `fpt_ci_replace`             — Friendly alias for the ci.replace action.
 * - `fpt_ci_clean`               — Friendly alias for the ci.clean action.
 * - `fpt_gitlab_review`          — AI review a GitLab Merge Request.
 * - `fpt_gitlab_analyze`         — Static analysis for a Merge Request.
 * - `fpt_zentao_report_start`    — Start today's Zentao daily report task.
 * - `fpt_zentao_report_finish`   — Finish a Zentao daily report task.
 * - `fpt_zentao_report_close`    — Close a Zentao daily report task.
 * - `fpt_zentao_report_edit`     — Edit a Zentao daily report task.
 * - `fpt_zentao_report_get`      — View a Zentao daily report task.
 * - `fpt_attendance_status`      — View today's attendance status.
 * - `fpt_attendance_checkin`     — Record today's check-in time.
 * - `fpt_attendance_subscribe`   — Subscribe to attendance reminders.
 * - `fpt_attendance_unsubscribe` — Unsubscribe from attendance reminders.
 * - `fpt_admin_apikeys_list`     — List your API keys.
 * - `fpt_admin_apikeys_add`      — Create a new API key.
 * - `fpt_admin_apikeys_remove`   — Delete an API key.
 * - `fpt_admin_logs_tail`        — Read the last N lines of server.log.
 * - `fpt_cron_run`               — Run a scheduled job immediately.
 * - `fpt_hot_reload`             — Pull latest code and hot reload (admin-only).
 * - `fpt_restart`                — Pull latest code and restart the process (admin-only).
 * - `fpt_invoke_action`          — Generic dispatch for any action by name.
 *
 * @param server The MCP Server instance where the tools will be registered.
 */
export function registerTools(server: McpServer): void {
  registerMetaTools(server, client);
  registerJobTools(server, client);
  registerBuildTools(server, client);
  registerGitlabTools(server, client);
  registerZentaoTools(server, client);
  registerAttendanceTools(server, client);
  registerAdminTools(server, client);
  registerActionTools(server, client);
}
