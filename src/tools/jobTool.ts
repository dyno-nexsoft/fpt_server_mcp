import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { FptServerClient } from '../fptClient.js';
import { jobToMarkdown, jobsToMarkdown, Job } from '../utils/jobFormatter.js';
import { mcpText } from '../utils/mcpResponse.js';

const JOB_STATES = ['queued', 'running', 'succeeded', 'failed', 'cancelled', 'interrupted'] as const;

/**
 * Registers job lifecycle tools: list/get/log/cancel/promote/retry.
 *
 * There is intentionally no SSE-streaming tool here — an MCP tool call is
 * request/response, not a long-lived connection, so real-time log tailing
 * is exposed instead as `fpt_get_job_log`'s offset-based polling
 * (`?offset=` in, `X-Log-Next-Offset` out), which a caller can loop on.
 */
export function registerJobTools(server: McpServer, client: FptServerClient): void {
  server.registerTool(
    'fpt_list_jobs',
    {
      description: 'List jobs, newest first. Optionally filter by state and cap the count.',
      inputSchema: {
        state: z.enum(JOB_STATES).optional().describe('Filter by exact job state'),
        limit: z.number().int().optional().describe('Max jobs to return (default 50, clamped 1..200)'),
      },
    },
    async ({ state, limit }) => {
      const query = new URLSearchParams();
      if (state) query.set('state', state);
      if (limit !== undefined) query.set('limit', String(limit));
      const qs = query.toString();
      const { jobs } = await client.get<{ jobs: Job[] }>(`/jobs${qs ? `?${qs}` : ''}`);
      return mcpText(jobsToMarkdown(jobs));
    }
  );

  server.registerTool(
    'fpt_get_job',
    {
      description: 'Get full detail of one job by id.',
      inputSchema: {
        id: z.string().describe('Job id, e.g. j-m3k9x2a7f-1a2'),
      },
    },
    async ({ id }) => {
      const job = await client.get<Job>(`/jobs/${encodeURIComponent(id)}`);
      return mcpText(jobToMarkdown(job));
    }
  );

  server.registerTool(
    'fpt_get_job_log',
    {
      description:
        'Fetch a slice of a job\'s build log starting at `offset` (polling alternative to SSE). ' +
        'Call again with the returned `nextOffset` to continue tailing an in-progress build.',
      inputSchema: {
        id: z.string().describe('Job id'),
        offset: z.number().int().optional().describe('Byte offset to resume from (default 0)'),
      },
    },
    async ({ id, offset }) => {
      const qs = offset !== undefined ? `?offset=${offset}` : '';
      const { data, headers } = await client.getWithHeaders<string>(`/jobs/${encodeURIComponent(id)}/log${qs}`);
      const nextOffset = headers['x-log-next-offset'];
      const body = typeof data === 'string' ? data : JSON.stringify(data);
      return mcpText(`${body}\n\n---\nnextOffset: ${nextOffset ?? 'unknown'}`);
    }
  );

  server.registerTool(
    'fpt_cancel_job',
    {
      description: 'Cancel a job. Fails with 409 if it already finished.',
      inputSchema: {
        id: z.string().describe('Job id'),
      },
    },
    async ({ id }) => {
      const job = await client.post<Job>(`/jobs/${encodeURIComponent(id)}/cancel`);
      return mcpText(`### Cancelled\n\n${jobToMarkdown(job)}`);
    }
  );

  server.registerTool(
    'fpt_promote_job',
    {
      description:
        'Promote a queued job into the parallel lane (fresh workspace clone). ' +
        'Fails with 409 for scripts that ignore `--now`.',
      inputSchema: {
        id: z.string().describe('Job id'),
      },
    },
    async ({ id }) => {
      const job = await client.post<Job>(`/jobs/${encodeURIComponent(id)}/promote`);
      return mcpText(`### Promoted\n\n${jobToMarkdown(job)}`);
    }
  );

  server.registerTool(
    'fpt_retry_job',
    {
      description: 'Re-invoke the action recorded on a finished job as a new job.',
      inputSchema: {
        id: z.string().describe('Job id to retry'),
      },
    },
    async ({ id }) => {
      const job = await client.post<Job>(`/jobs/${encodeURIComponent(id)}/retry`);
      return mcpText(`### Retried as new job\n\n${jobToMarkdown(job)}`);
    }
  );
}
