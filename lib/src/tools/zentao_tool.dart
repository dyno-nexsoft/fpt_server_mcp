import 'dart:convert';

import 'package:dart_mcp/server.dart';
import '../server.dart';

import '../fpt_client.dart';
import '../mcp_response.dart';

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
              Schema.string(description: 'Nội dung báo cáo (Markdown)'),
        },
        required: ['description'],
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/zentao.report.start',
        request.arguments ?? const {},
      );
      return mcpText(
        '- **task_id**: ${result['task_id']}\n- **summary**: ${result['summary']}',
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_finish',
      description:
          "Mark today's daily report task as finished (zentao.report.finish).",
      inputSchema: Schema.object(
        properties: {'task_id': Schema.int(description: 'ID task Zentao')},
        required: ['task_id'],
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/zentao.report.finish',
        request.arguments ?? const {},
      );
      return mcpText(const JsonEncoder.withIndent('  ').convert(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_close',
      description: 'Close a completed daily report task (zentao.report.close).',
      inputSchema: Schema.object(
        properties: {'task_id': Schema.int(description: 'ID task Zentao')},
        required: ['task_id'],
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/zentao.report.close',
        request.arguments ?? const {},
      );
      return mcpText(const JsonEncoder.withIndent('  ').convert(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_edit',
      description:
          'Edit the content of a daily report task (zentao.report.edit).',
      inputSchema: Schema.object(
        properties: {
          'task_id': Schema.int(description: 'ID task Zentao'),
          'description': Schema.string(description: 'Nội dung mới (Markdown)'),
        },
        required: ['task_id', 'description'],
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/zentao.report.edit',
        request.arguments ?? const {},
      );
      return mcpText(const JsonEncoder.withIndent('  ').convert(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_zentao_report_get',
      description:
          'View full detail of a daily report task (zentao.report.get).',
      inputSchema: Schema.object(
        properties: {'task_id': Schema.int(description: 'ID task Zentao')},
        required: ['task_id'],
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/zentao.report.get',
        request.arguments ?? const {},
      );
      return mcpText(const JsonEncoder.withIndent('  ').convert(result));
    },
  );
}
