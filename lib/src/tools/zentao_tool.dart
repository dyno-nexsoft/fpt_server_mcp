import 'package:dart_mcp/server.dart';
import 'package:fpt_server_shared/fpt_server_shared.dart';

import '../fpt_client.dart';
import '../markdown.dart';
import '../mcp_response.dart';
import '../server.dart';

/// Registers the `zentao.report.*`/`zentao.unlink` tools. Every one of these
/// requires the caller's Discord account to already be linked to a Zentao
/// account — `zentao.link` itself is withheld from REST (needs a password,
/// which can't travel through a JSON body).
void registerZentaoTools(FptMcpServer server, FptClient client) {
  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_start',
      description:
          "Create and start today's daily report task (zentao.report.start).",
      inputSchema: Schema.object(
        properties: {
          'description':
              Schema.string(description: 'Report content (Markdown)'),
        },
        required: ['description'],
      ),
    ),
    (request) async {
      final started = await client.zentaoReportStart(
        ZentaoReportStartParams(description: _description(request)),
      );
      return mcpText('${started.message}\n\n- **task_id**: ${started.taskId}');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_finish',
      description:
          "Mark today's daily report task as finished (zentao.report.finish).",
      inputSchema: Schema.object(
        properties: {'task_id': Schema.int(description: 'Zentao task id')},
        required: ['task_id'],
      ),
    ),
    (request) async {
      final result = await client
          .zentaoReportFinish(ZentaoTaskParams(taskId: _taskId(request)));
      return mcpText(result.message);
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_close',
      description: 'Close a completed daily report task (zentao.report.close).',
      inputSchema: Schema.object(
        properties: {'task_id': Schema.int(description: 'Zentao task id')},
        required: ['task_id'],
      ),
    ),
    (request) async {
      final result = await client
          .zentaoReportClose(ZentaoTaskParams(taskId: _taskId(request)));
      return mcpText(result.message);
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_edit',
      description:
          'Edit the content of a daily report task (zentao.report.edit).',
      inputSchema: Schema.object(
        properties: {
          'task_id': Schema.int(description: 'Zentao task id'),
          'description': Schema.string(description: 'New content (Markdown)'),
        },
        required: ['task_id', 'description'],
      ),
    ),
    (request) async {
      final result = await client.zentaoReportEdit(
        ZentaoReportEditParams(
          taskId: _taskId(request),
          description: _description(request),
        ),
      );
      return mcpText(result.message);
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_get',
      description:
          'View full detail of a daily report task (zentao.report.get).',
      inputSchema: Schema.object(
        properties: {'task_id': Schema.int(description: 'Zentao task id')},
        required: ['task_id'],
      ),
    ),
    (request) async {
      final task = await client
          .zentaoReportGet(ZentaoTaskParams(taskId: _taskId(request)));
      return mcpText(resultToMarkdown(task.toJson()));
    },
  );
}

int _taskId(CallToolRequest request) =>
    (request.arguments!['task_id'] as num).toInt();

String _description(CallToolRequest request) =>
    request.arguments?['description'] as String? ?? '';
