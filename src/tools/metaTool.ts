import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { FptServerClient } from '../fptClient.js';
import { jobsToMarkdown, Job } from '../utils/jobFormatter.js';
import { mcpText } from '../utils/mcpResponse.js';

interface ActionParam {
  name: string;
  description: string;
  type: 'string' | 'integer' | 'number' | 'boolean' | 'enumeration';
  required: boolean;
  choices?: string[];
  default?: unknown;
}

interface ActionSchema {
  name: string;
  description: string;
  kind: 'query' | 'mutation' | 'job';
  permission: 'read' | 'invoke' | 'invokeDangerous' | 'admin';
  params: ActionParam[];
}

function paramsToMarkdown(params: ActionParam[]): string {
  if (params.length === 0) return '_No parameters._';
  return params
    .map((p) => {
      const req = p.required ? '**required**' : 'optional';
      const choices = p.choices ? `, choices: ${p.choices.join('/')}` : '';
      const def = p.default !== undefined ? `, default: ${JSON.stringify(p.default)}` : '';
      return `- \`${p.name}\` (${p.type}, ${req}${choices}${def}) — ${p.description}`;
    })
    .join('\n');
}

/**
 * Registers read-only tools for server health/status and the self-describing
 * action catalogue (`GET /actions`), which lets a caller discover every
 * REST-exposed action without reading the Dart source.
 */
export function registerMetaTools(server: McpServer, client: FptServerClient): void {
  server.registerTool(
    'fpt_health',
    {
      description: 'Liveness probe for the fpt_server REST API. No auth required.',
      inputSchema: {},
    },
    async () => {
      const health = await client.get<any>('/health');
      return mcpText(
        `- **ok**: ${health.ok}\n- **version**: ${health.version}\n- **uptimeSeconds**: ${health.uptimeSeconds}\n- **hostname**: ${health.hostname}\n- **publicUrl**: ${health.publicUrl}`
      );
    }
  );

  server.registerTool(
    'fpt_status',
    {
      description: 'Queue state and environment: Dart version, uptime, running and queued jobs.',
      inputSchema: {},
    },
    async () => {
      const status = await client.get<any>('/status');
      const header = [
        `- **hostname**: ${status.hostname}`,
        `- **dartVersion**: ${status.dartVersion}`,
        `- **uptime**: ${status.uptime}`,
        `- **workingDirectory**: ${status.workingDirectory}`,
      ].join('\n');
      const running = jobsToMarkdown((status.running || []) as Job[]);
      const queued = jobsToMarkdown((status.queued || []) as Job[]);
      return mcpText(`${header}\n\n### Running\n\n${running}\n\n### Queued\n\n${queued}`);
    }
  );

  server.registerTool(
    'fpt_list_actions',
    {
      description:
        'Catalogue of every REST-exposed action with its permission and kind (query/mutation/job). Use fpt_describe_action for a specific action\'s full parameter schema.',
      inputSchema: {},
    },
    async () => {
      const { actions } = await client.get<{ actions: ActionSchema[] }>('/actions');
      const rows = actions
        .map((a) => `| \`${a.name}\` | ${a.kind} | ${a.permission} | ${a.description} |`)
        .join('\n');
      return mcpText(
        `| Action | Kind | Permission | Description |\n| --- | --- | --- | --- |\n${rows}`
      );
    }
  );

  server.registerTool(
    'fpt_describe_action',
    {
      description: "Full parameter schema for one action, by name (e.g. 'ci.build').",
      inputSchema: {
        name: z.string().describe("Action name, e.g. 'ci.build'"),
      },
    },
    async ({ name }) => {
      const action = await client.get<ActionSchema>(`/actions/${encodeURIComponent(name)}`);
      return mcpText(
        `### ${action.name}\n\n${action.description}\n\n- **kind**: ${action.kind}\n- **permission**: ${action.permission}\n\n**Params**\n\n${paramsToMarkdown(action.params)}`
      );
    }
  );
}
