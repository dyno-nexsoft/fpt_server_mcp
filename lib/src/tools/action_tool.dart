import 'package:dart_mcp/server.dart';
import 'package:nexsoft_server_shared/nexsoft_server_shared.dart' as shared;

import '../job_formatter.dart';
import '../markdown.dart';
import '../mcp_response.dart';
import '../nexsoft_client.dart';
import '../server.dart';

bool _looksLikeJob(Map<String, dynamic> data) =>
    data['state'] is String && data['action_name'] is String;

/// Registers the generic dispatch tool that reaches every REST-exposed
/// action by name, mirroring `POST /actions/{name}` directly. This is the
/// fallback for anything not covered by a dedicated tool (nexsoft_ci_build,
/// nexsoft_cancel_job, ...) — new server-side actions need no new tool here.
/// Use `nexsoft_describe_action` first to see the param schema for a given name.
void registerActionTools(NexsoftMcpServer server, NexsoftClient client) {
  server.registerTool(
    Tool(
      name: 'nexsoft_invoke_action',
      description:
          'Generic dispatch: invoke any REST-exposed action by name (see '
          "nexsoft_list_actions / nexsoft_describe_action). Returns 202 with a job "
          "id for kind='job' actions, 200 with the result otherwise.",
      inputSchema: Schema.object(
        properties: {
          'name': Schema.string(
            description: "Action name, e.g. 'ci.build', 'ci.clean', 'cron.run'",
          ),
          'params': Schema.object(
            description:
                'Action-specific parameters, per nexsoft_describe_action',
          ),
        },
        required: ['name'],
      ),
    ),
    (request) async {
      final args = request.arguments!;
      final name = args['name'] as String;
      final params =
          (args['params'] as Map?)?.cast<String, Object?>() ?? const {};
      final result = await client.postJson(
        '/actions/${Uri.encodeComponent(name)}',
        params,
      );
      if (_looksLikeJob(result)) {
        return mcpText(jobToMarkdown(shared.Job.fromJson(result)));
      }
      return mcpText(resultToMarkdown(result));
    },
  );
}
