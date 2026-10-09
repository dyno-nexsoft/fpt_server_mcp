import 'package:dart_mcp/server.dart';
import 'package:fpt_server_shared/fpt_server_shared.dart';

import '../fpt_client.dart';
import '../markdown.dart';
import '../mcp_response.dart';
import '../server.dart';

/// How far back a `contains` filter looks — the most `admin.logs.tail` will
/// return in one call.
const _filterScanLines = 1000;

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
      return mcpText(apiKeysToMarkdown(await client.apiKeysList()));
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
            description: 'Display name (audit log, CREATED_BY on builds)',
          ),
        },
        required: ['name'],
      ),
    ),
    (request) async {
      final params =
          ApiKeyAddParams(name: request.arguments!['name'] as String);
      // Raw, not `client.apiKeysAdd`: the reply's name and scopes are worth
      // showing and the typed result keeps neither.
      final result =
          await client.invokeAction('admin.apiKeys.add', params.toJson());
      return mcpText(apiKeyCreatedToMarkdown(result));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_admin_apikeys_remove',
      description: 'Delete one of your API keys — an owner can delete any key '
          '(admin.apiKeys.remove).',
      inputSchema: Schema.object(
        properties: {
          'id': Schema.string(description: 'Id of the key to delete')
        },
        required: ['id'],
      ),
    ),
    (request) async {
      final result = await client.apiKeysRemove(
        ApiKeyRemoveParams(id: request.arguments!['id'] as String),
      );
      return mcpText(result.message);
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_admin_logs_tail',
      description: 'Read server.log for debugging (admin.logs.tail). '
          'Admin-only — the log records every request URL and is not '
          'otherwise reachable. By default the newest lines; every reply '
          'says which line numbers it shows and how long the log is, and '
          '`from_line`/`to_line` read any range by those numbers.',
      inputSchema: Schema.object(
        properties: {
          'lines': Schema.int(
            minimum: 1,
            maximum: 500,
            description: 'How many lines to return (default 100, max 500): '
                'the newest ones, or — with only `from_line` — that many '
                'starting there, or — with only `to_line` — that many ending '
                'there. The reply is also capped at about 12k characters, '
                'dropping the oldest lines first.',
          ),
          'source': UntitledSingleSelectEnumSchema(
            values: ['server', 'novnc'],
            description: 'Which log to read: `server` (the bot, default) or '
                '`novnc` (the remote-desktop service)',
          ),
          'from_line': Schema.int(
            minimum: 1,
            description: 'First line to return, by the absolute 1-based '
                'numbers a previous reply showed.',
          ),
          'to_line': Schema.int(
            minimum: 1,
            description: 'Last line to return, inclusive.',
          ),
          'contains': Schema.string(
            description: 'Only lines containing this text (case-insensitive) '
                '— searched across the last $_filterScanLines lines, or '
                'within the from/to range when one is given. Most of the log '
                'is one audit line per dashboard poll, so filtering (e.g. '
                '"SEVERE", "review", an error message) is usually the way to '
                'find what you want. Matches keep their real line numbers.',
          ),
        },
      ),
    ),
    (request) async {
      final args = request.arguments ?? const {};
      final lines = ((args['lines'] as num?)?.toInt() ?? 100).clamp(1, 500);
      final from = (args['from_line'] as num?)?.toInt();
      final to = (args['to_line'] as num?)?.toInt();
      final contains = (args['contains'] as String?)?.trim();
      final filtering = contains != null && contains.isNotEmpty;
      final ranged = from != null || to != null;
      // The shared params class spells the keys, so this cannot drift from
      // what the server reads.
      final params = LogsTailParams(
        // A filter needs the wider window to have anything to find; without
        // one there is no reason to fetch more than is shown. A range is
        // read as asked either way.
        lines: filtering && !ranged ? _filterScanLines : lines,
        source: args['source'] as String?,
        fromLine: from,
        toLine: to,
      );
      // Raw, not `client.logsTail`: the formatter tells a reply without
      // line numbers apart from one that starts at line 1.
      final result =
          await client.invokeAction('admin.logs.tail', params.toJson());
      return mcpText(
        logLinesToMarkdown(
          result,
          contains: contains,
          // A range was sized by the caller; only a tail is cut to `lines`.
          limit: ranged ? 500 : lines,
        ),
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_cron_run',
      description:
          'Run a scheduled job immediately (cron.run). Cron jobs clean '
          'caches, restart the process, and post to shared channels — '
          'requires invokeDangerous. The valid job names are whatever '
          'fpt_server currently has scheduled; an unknown name comes back '
          'as an error naming the live set, so there is no fixed list to '
          'remember here.',
      inputSchema: Schema.object(
        properties: {
          'job': Schema.string(description: 'Scheduled job name'),
        },
        required: ['job'],
      ),
    ),
    (request) async {
      final result = await client.cronRun(
        CronRunParams(job: request.arguments!['job'] as String),
      );
      return mcpText(result.message);
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
      final result = await client.hotReload();
      return mcpText(result.message);
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
      final params = RestartParams(
        whenIdle: request.arguments?['when_idle'] as bool? ?? false,
      );
      final result = await client.restart(params);
      return mcpText(result.message);
    },
  );
}
