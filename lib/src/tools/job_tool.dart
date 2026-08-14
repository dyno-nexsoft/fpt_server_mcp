import 'package:dart_mcp/server.dart';
import '../server.dart';
import 'package:fpt_server_shared/fpt_server_shared.dart';

import '../fpt_client.dart';
import '../job_formatter.dart';
import '../mcp_response.dart';

const _jobStates = [
  'queued',
  'running',
  'succeeded',
  'failed',
  'cancelled',
  'interrupted',
];

/// Registers job lifecycle tools: list/get/log/cancel/promote/retry.
///
/// There is intentionally no SSE-streaming tool here — an MCP tool call is
/// request/response, not a long-lived connection, so real-time log tailing
/// is exposed instead as `fpt_get_job_log`'s offset-based polling
/// (`?offset=` in, `X-Log-Next-Offset` out), which a caller can loop on.
void registerJobTools(FptMcpServer server, FptClient client) {
  server.registerTool(
    Tool(
      name: 'fpt_list_jobs',
      description:
          'List jobs, newest first. Optionally filter by state and cap the count.',
      inputSchema: Schema.object(
        properties: {
          'state': UntitledSingleSelectEnumSchema(
            values: _jobStates,
            description: 'Filter by exact job state',
          ),
          'limit': Schema.int(
            description: 'Max jobs to return (default 50, clamped 1..200)',
          ),
        },
      ),
    ),
    (request) async {
      final args = request.arguments ?? const {};
      final query = <String, String>{
        if (args['state'] case final state?) 'state': state as String,
        if (args['limit'] case final limit?) 'limit': '$limit',
      };
      final qs = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
      final json = await client.getJson('/jobs$qs');
      final jobs = (json['jobs'] as List)
          .map((j) => Job.fromJson(j as Map<String, dynamic>))
          .toList();
      return mcpText(jobsToMarkdown(jobs));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_get_job',
      description: 'Get full detail of one job by id.',
      inputSchema: Schema.object(
        properties: {
          'id': Schema.string(description: 'Job id, e.g. j-m3k9x2a7f-1a2'),
        },
        required: ['id'],
      ),
    ),
    (request) async {
      final id = request.arguments!['id'] as String;
      final job = Job.fromJson(
        await client.getJson('/jobs/${Uri.encodeComponent(id)}'),
      );
      return mcpText(jobToMarkdown(job));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_get_job_log',
      description:
          "Fetch a slice of a job's build log starting at `offset` (polling "
          'alternative to SSE). Call again with the returned `nextOffset` to '
          'continue tailing an in-progress build.',
      inputSchema: Schema.object(
        properties: {
          'id': Schema.string(description: 'Job id'),
          'offset':
              Schema.int(description: 'Byte offset to resume from (default 0)'),
        },
        required: ['id'],
      ),
    ),
    (request) async {
      final args = request.arguments!;
      final id = args['id'] as String;
      final offset = args['offset'];
      final qs = offset != null ? '?offset=$offset' : '';
      final result = await client.getWithHeaders(
        '/jobs/${Uri.encodeComponent(id)}/log$qs',
      );
      final nextOffset = result.headers['x-log-next-offset'] ?? 'unknown';
      return mcpText('${result.body}\n\n---\nnextOffset: $nextOffset');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_cancel_job',
      description: 'Cancel a job. Fails with 409 if it already finished.',
      inputSchema: Schema.object(
        properties: {'id': Schema.string(description: 'Job id')},
        required: ['id'],
      ),
    ),
    (request) async {
      final id = request.arguments!['id'] as String;
      final job = Job.fromJson(
        await client.postJson('/jobs/${Uri.encodeComponent(id)}/cancel'),
      );
      return mcpText('### Cancelled\n\n${jobToMarkdown(job)}');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_promote_job',
      description:
          'Promote a queued job into the parallel lane (fresh workspace '
          "clone). Fails with 409 for scripts that ignore `--now`.",
      inputSchema: Schema.object(
        properties: {'id': Schema.string(description: 'Job id')},
        required: ['id'],
      ),
    ),
    (request) async {
      final id = request.arguments!['id'] as String;
      final job = Job.fromJson(
        await client.postJson('/jobs/${Uri.encodeComponent(id)}/promote'),
      );
      return mcpText('### Promoted\n\n${jobToMarkdown(job)}');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_retry_job',
      description:
          'Re-invoke the action recorded on a finished job as a new job.',
      inputSchema: Schema.object(
        properties: {'id': Schema.string(description: 'Job id to retry')},
        required: ['id'],
      ),
    ),
    (request) async {
      final id = request.arguments!['id'] as String;
      final job = Job.fromJson(
        await client.postJson('/jobs/${Uri.encodeComponent(id)}/retry'),
      );
      return mcpText('### Retried as new job\n\n${jobToMarkdown(job)}');
    },
  );
}
