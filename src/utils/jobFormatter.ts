/**
 * Shape of a job as documented in `docs/rest-api.md` (`POST /builds`,
 * `GET /jobs`, `GET /jobs/{id}`). `log_url`/`warnings` only appear on the
 * job-creation response.
 */
export interface Job {
  id: string;
  state: 'queued' | 'running' | 'succeeded' | 'failed' | 'cancelled' | 'interrupted';
  command: string;
  action_name: string;
  action_params: Record<string, unknown>;
  created_by: string;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
  exit_code: number | null;
  last_line: string | null;
  promoted: boolean;
  log_url?: string;
  warnings?: string[];
  [key: string]: unknown;
}

/** Renders a single job as compact Markdown instead of dumping the raw JSON. */
export function jobToMarkdown(job: Job): string {
  const lines = [
    `- **id**: \`${job.id}\``,
    `- **state**: ${job.state}${job.promoted ? ' (promoted)' : ''}`,
    `- **action**: ${job.action_name} \`${JSON.stringify(job.action_params)}\``,
    `- **created_by**: ${job.created_by}`,
    `- **created_at**: ${job.created_at}`,
  ];
  if (job.started_at) lines.push(`- **started_at**: ${job.started_at}`);
  if (job.finished_at) lines.push(`- **finished_at**: ${job.finished_at}`);
  if (job.exit_code !== null && job.exit_code !== undefined) lines.push(`- **exit_code**: ${job.exit_code}`);
  if (job.last_line) lines.push(`- **last_line**: ${job.last_line}`);
  if (job.log_url) lines.push(`- **log_url**: ${job.log_url}`);
  if (job.warnings?.length) lines.push(`- **warnings**: ${job.warnings.join('; ')}`);
  return lines.join('\n');
}

/** Renders a list of jobs, one compact block each, separated by a rule. */
export function jobsToMarkdown(jobs: Job[]): string {
  if (jobs.length === 0) return '_No jobs found._';
  return jobs.map(jobToMarkdown).join('\n\n---\n\n');
}
