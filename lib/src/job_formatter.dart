import 'package:fpt_server_shared/fpt_server_shared.dart';

/// Renders a single job as compact Markdown instead of dumping raw JSON.
String jobToMarkdown(Job job) {
  final lines = [
    '- **id**: `${job.id}`',
    '- **state**: ${job.state.toWire()}${job.promoted ? ' (promoted)' : ''}',
    '- **action**: ${job.actionName ?? job.command} `${job.actionParams}`',
    if (job.createdBy != null) '- **created_by**: ${job.createdBy}',
    '- **created_at**: ${job.createdAt.toIso8601String()}',
  ];
  if (job.startedAt != null) {
    lines.add('- **started_at**: ${job.startedAt!.toIso8601String()}');
  }
  if (job.finishedAt != null) {
    lines.add('- **finished_at**: ${job.finishedAt!.toIso8601String()}');
  }
  if (job.exitCode != null) lines.add('- **exit_code**: ${job.exitCode}');
  if (job.lastLine != null) lines.add('- **last_line**: ${job.lastLine}');
  if (job.logUrl != null) lines.add('- **log_url**: ${job.logUrl}');
  if (job.warnings.isNotEmpty) {
    lines.add('- **warnings**: ${job.warnings.join('; ')}');
  }
  return lines.join('\n');
}

/// Renders a list of jobs, one compact block each, separated by a rule.
String jobsToMarkdown(List<Job> jobs) {
  if (jobs.isEmpty) return '_No jobs found._';
  return jobs.map(jobToMarkdown).join('\n\n---\n\n');
}
