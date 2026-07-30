import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { FptServerClient } from '../fptClient.js';
import { mcpText } from '../utils/mcpResponse.js';

const CRON_JOBS = [
  'CleanupCacheJob',
  'DailyReportStartJob',
  'MrReviewCheckJob',
  'AttendanceReminderJob',
  'AttendanceCheckoutJob',
  'AttendanceDisableButtonsJob',
  'DailyReportReminderJob',
  'LunchReminderJob',
  'WorkResumeReminderJob',
  'DailyReportEndJob',
] as const;

/**
 * Registers `admin.apiKeys.*`, `admin.owners.*`, and `cron.run` — the
 * elevated-permission maintenance actions (`invoke`/`admin`/`invokeDangerous`).
 */
export function registerAdminTools(server: McpServer, client: FptServerClient): void {
  server.registerTool(
    'fpt_admin_apikeys_list',
    {
      description: 'List your API keys — an owner sees every key (admin.apiKeys.list).',
      inputSchema: {},
    },
    async () => {
      const result = await client.post<any>('/actions/admin.apiKeys.list', {});
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_admin_apikeys_add',
    {
      description:
        'Create a new API key for yourself (admin.apiKeys.add). The response includes `secret`, shown exactly ' +
        'once — only its hash is persisted server-side.',
      inputSchema: {
        name: z.string().describe('Tên hiển thị (audit log, CREATED_BY trên build)'),
      },
    },
    async ({ name }) => {
      const result = await client.post<any>('/actions/admin.apiKeys.add', { name });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_admin_apikeys_remove',
    {
      description: 'Delete one of your API keys — an owner can delete any key (admin.apiKeys.remove).',
      inputSchema: {
        id: z.string().describe('Định danh key cần xoá'),
      },
    },
    async ({ id }) => {
      const result = await client.post<any>('/actions/admin.apiKeys.remove', { id });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_admin_logs_tail',
    {
      description:
        "Read the last N lines of server.log for debugging (admin.logs.tail). Admin-only — the log records " +
        'every request URL and is not otherwise reachable.',
      inputSchema: {
        lines: z
          .number()
          .int()
          .min(1)
          .max(1000)
          .optional()
          .describe('Số dòng cuối muốn xem (mặc định 200, tối đa 1000)'),
      },
    },
    async ({ lines }) => {
      const result = await client.post<any>('/actions/admin.logs.tail', { lines });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_cron_run',
    {
      description:
        'Run a scheduled job immediately (cron.run). Cron jobs clean caches, restart the process, and post to ' +
        'shared channels — requires invokeDangerous.',
      inputSchema: {
        job: z.enum(CRON_JOBS).describe('Scheduled job name'),
      },
    },
    async ({ job }) => {
      const result = await client.post<any>('/actions/cron.run', { job });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );
}
