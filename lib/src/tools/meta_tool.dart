import 'package:dart_mcp/server.dart';
import '../server.dart';
import 'package:fpt_server_shared/fpt_server_shared.dart';

import '../fpt_client.dart';
import '../job_formatter.dart';
import '../mcp_response.dart';

String _paramsToMarkdown(List<ActionParam> params) {
  if (params.isEmpty) return '_No parameters._';
  return params.map((p) {
    final req = p.isRequired ? '**required**' : 'optional';
    final choices =
        p.choices.isNotEmpty ? ', choices: ${p.choices.join('/')}' : '';
    final def = p.defaultValue != null ? ', default: ${p.defaultValue}' : '';
    return '- `${p.name}` (${p.type.toWire()}, $req$choices$def) — ${p.description}';
  }).join('\n');
}

/// Registers read-only tools for server health/status and the
/// self-describing action catalogue (`GET /actions`), which lets a caller
/// discover every REST-exposed action without reading the Dart source.
void registerMetaTools(FptMcpServer server, FptClient client) {
  server.registerTool(
    Tool(
      name: 'fpt_health',
      description:
          'Liveness probe for the fpt_server REST API. No auth required.',
      inputSchema: Schema.object(),
    ),
    (request) async {
      final health = Health.fromJson(await client.getJson('/health'));
      return mcpText(
        '- **ok**: ${health.ok}\n'
        '- **version**: ${health.version}\n'
        '- **appVersion**: ${health.appVersion}\n'
        '- **uptimeSeconds**: ${health.uptimeSeconds}\n'
        '- **hostname**: ${health.hostname}',
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_status',
      description:
          'Queue state and environment: Dart version, uptime, running and queued jobs.',
      inputSchema: Schema.object(),
    ),
    (request) async {
      final status = SystemStatus.fromJson(await client.getJson('/status'));
      final header = [
        '- **hostname**: ${status.hostname}',
        '- **dartVersion**: ${status.dartVersion}',
        '- **uptime**: ${status.uptime}',
        '- **workingDirectory**: ${status.workingDirectory}',
      ].join('\n');
      final running = jobsToMarkdown(status.running);
      final queued = jobsToMarkdown(status.queued);
      return mcpText(
        '$header\n\n### Running\n\n$running\n\n### Queued\n\n$queued',
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_list_actions',
      description:
          'Catalogue of every REST-exposed action with its permission and '
          "kind (query/mutation/job). Use fpt_describe_action for a specific "
          "action's full parameter schema.",
      inputSchema: Schema.object(),
    ),
    (request) async {
      final json = await client.getJson('/actions');
      final actions = (json['actions'] as List)
          .map((a) => ActionSchema.fromJson(a as Map<String, dynamic>))
          .toList();
      final rows = actions
          .map(
            (a) =>
                '| `${a.name}` | ${a.kind.name} | ${a.permission.toWire()} | ${a.description} |',
          )
          .join('\n');
      return mcpText(
        '| Action | Kind | Permission | Description |\n'
        '| --- | --- | --- | --- |\n$rows',
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_describe_action',
      description:
          "Full parameter schema for one action, by name (e.g. 'ci.build').",
      inputSchema: Schema.object(
        properties: {
          'name': Schema.string(description: "Action name, e.g. 'ci.build'"),
        },
        required: ['name'],
      ),
    ),
    (request) async {
      final name = request.arguments!['name'] as String;
      final action = ActionSchema.fromJson(
        await client.getJson('/actions/${Uri.encodeComponent(name)}'),
      );
      return mcpText(
        '### ${action.name}\n\n${action.description}\n\n'
        '- **kind**: ${action.kind.name}\n'
        '- **permission**: ${action.permission.toWire()}\n\n'
        '**Params**\n\n${_paramsToMarkdown(action.params)}',
      );
    },
  );
}
