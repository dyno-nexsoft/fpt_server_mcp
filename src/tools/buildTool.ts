import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { FptServerClient } from '../fptClient.js';
import { jobToMarkdown, Job } from '../utils/jobFormatter.js';
import { mcpText } from '../utils/mcpResponse.js';

const BUILD_PLATFORMS = ['android', 'ios', 'mobile', 'macos', 'windows', 'desktop'] as const;
const BUILD_ENVIRONMENTS = ['dev', 'test', 'prod'] as const;

/**
 * Friendly wrappers around the `ci.*` action group's REST aliases
 * (`POST /builds`, `/gen`, `/replace`, `/cleans`). Purely convenience —
 * `fpt_invoke_action` reaches the same endpoints; these tools just give
 * them discoverable names and typed params for the common case.
 */
export function registerBuildTools(server: McpServer, client: FptServerClient): void {
  server.registerTool(
    'fpt_ci_build',
    {
      description:
        'Trigger a CI build job (POST /builds, alias for the ci.build action). Returns immediately with a queued/running job.',
      inputSchema: {
        tbchat: z.string().describe('Branch repo tbchat'),
        database: z.string().describe('Branch repo database'),
        im: z.string().optional().describe('Branch module Instant Message'),
        wallet: z.string().optional().describe('Branch module Wallet'),
        cloud_storage: z.string().optional().describe('Branch module Cloud Storage'),
        socialfi: z.string().optional().describe('Branch module Socialfi'),
        platform: z.enum(BUILD_PLATFORMS).optional().describe('Platform to build (default: mobile)'),
        environment: z.enum(BUILD_ENVIRONMENTS).optional().describe('Build environment (default: dev)'),
        release_notes: z.string().optional().describe('Ghi chú phát hành'),
      },
    },
    async (params) => {
      const job = await client.post<Job>('/builds', params);
      return mcpText(`### Build queued\n\n${jobToMarkdown(job)}`);
    }
  );

  server.registerTool(
    'fpt_ci_gen',
    {
      description:
        'Generate proto and API docs for socialfi (POST /gen, alias for ci.gen). Returns a queued/running job.',
      inputSchema: {
        environment: z.enum(BUILD_ENVIRONMENTS).optional().describe('Build environment (default: dev)'),
        socialfi: z.string().optional().describe('Branch module Socialfi; empty = default per environment'),
      },
    },
    async (params) => {
      const job = await client.post<Job>('/gen', params);
      return mcpText(`### Gen queued\n\n${jobToMarkdown(job)}`);
    }
  );

  server.registerTool(
    'fpt_ci_replace',
    {
      description:
        'Replace the SDK inside tbchat (POST /replace, alias for ci.replace). Returns a queued/running job.',
      inputSchema: {
        url: z.string().describe('URL của SDK'),
        tbchat: z.string().describe('Branch repo tbchat'),
      },
    },
    async (params) => {
      const job = await client.post<Job>('/replace', params);
      return mcpText(`### Replace queued\n\n${jobToMarkdown(job)}`);
    }
  );

  server.registerTool(
    'fpt_ci_clean',
    {
      description:
        'Clean build artifacts and dependencies (POST /cleans, alias for ci.clean). Runs `git clean` under the hood ' +
        '— recoverable, but requires invokeDangerous. Returns a queued/running job.',
      inputSchema: {
        mode: z.enum(['--full', '--files']).optional().describe('Empty = same as /cleans with no mode'),
      },
    },
    async (params) => {
      const job = await client.post<Job>('/cleans', params);
      return mcpText(`### Clean queued\n\n${jobToMarkdown(job)}`);
    }
  );
}
