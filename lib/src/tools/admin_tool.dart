import 'dart:convert';

import 'package:dart_mcp/server.dart';
import '../server.dart';

import '../fpt_client.dart';
import '../mcp_response.dart';

const _cronJobs = [
  'CleanupCacheJob',
  'DailyReportStartJob',
  'AttendanceReminderJob',
  'AttendanceCheckoutJob',
  'AttendanceDisableButtonsJob',
  'DailyReportReminderJob',
  'LunchReminderJob',
  'WorkResumeReminderJob',
  'DailyReportEndJob',
];

String _pretty(Map<String, dynamic> json) =>
    const JsonEncoder.withIndent('  ').convert(json);

/// Registers `admin.apiKeys.*`, `cron.run`, and `system.hotReload`/
/// `system.restart` — the elevated-permission maintenance actions
/// (`invoke`/`admin`/`invokeDangerous`).
///
/// `system.hotReload`/`system.restart` need an `admin`-tier API key, same as
/// `admin.logs.tail`. `system.shutdown` is deliberately not here: it has no
/// automatic recovery path, so the server keeps it off the REST surface
/// entirely (reachable only via the Discord button's confirmation modal).
/// Hold an admin key used for these two as privately as an SSH credential —
/// `system.restart` runs `git pull` then reloads the process, so a leaked
/// key is remote code execution on the build machine, not just an unwanted
/// restart.
void registerAdminTools(FptMcpServer server, FptClient client) {
  server.registerTool(
    Tool(
      name: 'fpt_admin_apikeys_list',
      description:
          'List your API keys — an owner sees every key (admin.apiKeys.list).',
      inputSchema: Schema.object(),
    ),
    (request) async {
      final result = await client.postJson('/actions/admin.apiKeys.list');
      return mcpText(_pretty(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_admin_apikeys_add',
      description: 'Create a new API key for yourself (admin.apiKeys.add). The '
          'response includes `secret`, shown exactly once — only its hash '
          'is persisted server-side.',
      inputSchema: Schema.object(
        properties: {
          'name': Schema.string(
            description: 'Tên hiển thị (audit log, CREATED_BY trên build)',
          ),
        },
        required: ['name'],
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/admin.apiKeys.add',
        request.arguments ?? const {},
      );
      return mcpText(_pretty(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_admin_apikeys_remove',
      description: 'Delete one of your API keys — an owner can delete any key '
          '(admin.apiKeys.remove).',
      inputSchema: Schema.object(
        properties: {'id': Schema.string(description: 'Định danh key cần xoá')},
        required: ['id'],
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/admin.apiKeys.remove',
        request.arguments ?? const {},
      );
      return mcpText(_pretty(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_admin_logs_tail',
      description: 'Read the last N lines of server.log for debugging '
          '(admin.logs.tail). Admin-only — the log records every request '
          'URL and is not otherwise reachable.',
      inputSchema: Schema.object(
        properties: {
          'lines': Schema.int(
            minimum: 1,
            maximum: 1000,
            description: 'Số dòng cuối muốn xem (mặc định 200, tối đa 1000)',
          ),
        },
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/admin.logs.tail',
        request.arguments ?? const {},
      );
      return mcpText(_pretty(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_cron_run',
      description:
          'Run a scheduled job immediately (cron.run). Cron jobs clean '
          'caches, restart the process, and post to shared channels — '
          'requires invokeDangerous.',
      inputSchema: Schema.object(
        properties: {
          'job': UntitledSingleSelectEnumSchema(
            values: _cronJobs,
            description: 'Scheduled job name',
          ),
        },
        required: ['job'],
      ),
    ),
    (request) async {
      final result = await client.postJson(
        '/actions/cron.run',
        request.arguments ?? const {},
      );
      return mcpText(_pretty(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_hot_reload',
      description: 'Pull the latest code and hot reload without restarting the '
          'process (system.hotReload). Admin-only.',
      inputSchema: Schema.object(),
    ),
    (request) async {
      final result = await client.postJson('/actions/system.hotReload');
      return mcpText(_pretty(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_restart',
      description:
          'Pull the latest code, install dependencies, and restart the bot '
          'process (system.restart). Admin-only — the bot is briefly '
          'offline while the process reloads. Pass when_idle to wait until '
          'no builds are running or queued instead of restarting immediately '
          '(interrupting an in-flight build the moment it restarts).',
      inputSchema: Schema.object(
        properties: {
          'when_idle': Schema.bool(
            description: 'Wait until no builds are running or queued before '
                'restarting, instead of restarting right away',
          ),
        },
      ),
    ),
    (request) async {
      final whenIdle = request.arguments?['when_idle'] as bool?;
      final result = await client.postJson('/actions/system.restart', {
        if (whenIdle != null) 'when_idle': whenIdle,
      });
      return mcpText(_pretty(result));
    },
  );
}
