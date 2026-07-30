import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { FptServerClient } from '../fptClient.js';
import { jobToMarkdown, Job } from '../utils/jobFormatter.js';
import { mcpText } from '../utils/mcpResponse.js';

interface GitlabReviewResult {
  mr_iid: number;
  mr_title: string;
  mr_url: string;
  note_id: number;
  note_url: string;
  files_reviewed: number;
  total_files: number;
  skipped: string[];
}

/** Registers the `gitlab.*` action group's tools. */
export function registerGitlabTools(server: McpServer, client: FptServerClient): void {
  server.registerTool(
    'fpt_gitlab_review',
    {
      description:
        'AI review a GitLab Merge Request from its URL (gitlab.review). Blocks until the review is posted ' +
        '(a minute or two) — not a job, since there is no shell command or artifact directory behind it.',
      inputSchema: {
        url: z.string().describe('URL của Merge Request GitLab'),
      },
    },
    async ({ url }) => {
      const result = await client.post<GitlabReviewResult>('/actions/gitlab.review', { url });
      const lines = [
        `### Reviewed MR !${result.mr_iid} — ${result.mr_title}`,
        `- **mr_url**: ${result.mr_url}`,
        `- **note_url**: ${result.note_url}`,
        `- **files_reviewed**: ${result.files_reviewed}/${result.total_files}`,
      ];
      if (result.skipped?.length) lines.push(`- **skipped**: ${result.skipped.join(', ')}`);
      return mcpText(lines.join('\n'));
    }
  );

  server.registerTool(
    'fpt_gitlab_analyze',
    {
      description:
        'Run static analysis for a Merge Request (gitlab.analyze). Returns a queued/running job.',
      inputSchema: {
        urls: z.string().describe(
          'MR chính, kèm các MR submodule liên quan. Module không có MR dùng branch mặc định'
        ),
      },
    },
    async ({ urls }) => {
      const job = await client.post<Job>('/actions/gitlab.analyze', { urls });
      return mcpText(`### Analyze queued\n\n${jobToMarkdown(job)}`);
    }
  );
}
