import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { FptServerClient } from '../fptClient.js';
import { mcpText } from '../utils/mcpResponse.js';

/**
 * Registers the `zentao.report.*`/`zentao.unlink` tools. Every one of these
 * requires the caller's Discord account to already be linked to a Zentao
 * account — `zentao.link` itself is withheld from REST (needs a password,
 * which can't travel through a JSON body).
 */
export function registerZentaoTools(server: McpServer, client: FptServerClient): void {
  server.registerTool(
    'fpt_zentao_report_start',
    {
      description: "Create and start today's daily report task (zentao.report.start).",
      inputSchema: {
        description: z.string().describe('Nội dung báo cáo (Markdown)'),
      },
    },
    async ({ description }) => {
      const result = await client.post<{ task_id: number; summary: string }>('/actions/zentao.report.start', {
        description,
      });
      return mcpText(`- **task_id**: ${result.task_id}\n- **summary**: ${result.summary}`);
    }
  );

  server.registerTool(
    'fpt_zentao_report_finish',
    {
      description: "Mark today's daily report task as finished (zentao.report.finish).",
      inputSchema: {
        task_id: z.number().int().describe('ID task Zentao'),
      },
    },
    async ({ task_id }) => {
      const result = await client.post<any>('/actions/zentao.report.finish', { task_id });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_zentao_report_close',
    {
      description: 'Close a completed daily report task (zentao.report.close).',
      inputSchema: {
        task_id: z.number().int().describe('ID task Zentao'),
      },
    },
    async ({ task_id }) => {
      const result = await client.post<any>('/actions/zentao.report.close', { task_id });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_zentao_report_edit',
    {
      description: 'Edit the content of a daily report task (zentao.report.edit).',
      inputSchema: {
        task_id: z.number().int().describe('ID task Zentao'),
        description: z.string().describe('Nội dung mới (Markdown)'),
      },
    },
    async ({ task_id, description }) => {
      const result = await client.post<any>('/actions/zentao.report.edit', { task_id, description });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_zentao_report_get',
    {
      description: 'View full detail of a daily report task (zentao.report.get).',
      inputSchema: {
        task_id: z.number().int().describe('ID task Zentao'),
      },
    },
    async ({ task_id }) => {
      const result = await client.post<any>('/actions/zentao.report.get', { task_id });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );
}
