import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { FptServerClient } from '../fptClient.js';
import { jobToMarkdown, Job } from '../utils/jobFormatter.js';
import { mcpText } from '../utils/mcpResponse.js';

function looksLikeJob(data: any): data is Job {
  return data && typeof data === 'object' && typeof data.state === 'string' && typeof data.action_name === 'string';
}

/**
 * Registers the generic dispatch tool that reaches every REST-exposed
 * action by name, mirroring `POST /actions/{name}` directly. This is the
 * fallback for anything not covered by a dedicated tool (fpt_trigger_build,
 * fpt_cancel_job, ...) — new server-side actions need no new tool here.
 * Use `fpt_describe_action` first to see the param schema for a given name.
 */
export function registerActionTools(server: McpServer, client: FptServerClient): void {
  server.registerTool(
    'fpt_invoke_action',
    {
      description:
        "Generic dispatch: invoke any REST-exposed action by name (see fpt_list_actions / fpt_describe_action). " +
        "Returns 202 with a job id for kind='job' actions, 200 with the result otherwise.",
      inputSchema: {
        name: z.string().describe("Action name, e.g. 'ci.build', 'ci.clean', 'cron.run'"),
        params: z.record(z.unknown()).optional().describe('Action-specific parameters, per fpt_describe_action'),
      },
    },
    async ({ name, params }) => {
      const result = await client.post<any>(`/actions/${encodeURIComponent(name)}`, params ?? {});
      if (looksLikeJob(result)) {
        return mcpText(jobToMarkdown(result));
      }
      return mcpText(JSON.stringify(result, null, 2));
    }
  );
}
