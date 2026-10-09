import 'package:dart_mcp/server.dart';
import 'package:fpt_server_shared/fpt_server_shared.dart';

import '../fpt_client.dart';
import '../job_formatter.dart';
import '../mcp_response.dart';
import '../server.dart';

// Sourced from the shared enums themselves rather than hand-copied lists —
// the same class of drift hard constraint #4 warns about: `_buildPlatforms`
// previously spelled `mobile`/`desktop` next to `android`/`ios`/`macos`/
// `windows`, which quietly went stale the moment those two were renamed.
final _buildPlatforms = [for (final p in PlatformBuild.values) p.toWire()];
final _buildEnvironments = [for (final e in EnvironmentBuild.values) e.name];
final _repos = [for (final r in GitRepo.values) r.slug];

/// Friendly wrappers around the `ci.*` action group's REST aliases
/// (`POST /builds`, `/gen`, `/replace`, `/cleans`). Purely convenience —
/// `fpt_invoke_action` reaches the same endpoints; these tools just give
/// them discoverable names and typed params for the common case.
void registerBuildTools(FptMcpServer server, FptClient client) {
  server.registerTool(
    Tool(
      name: 'fpt_ci_build',
      description:
          'Trigger a CI build job (POST /builds, alias for the ci.build '
          'action). Returns immediately with a queued/running job.',
      inputSchema: Schema.object(
        properties: {
          'tbchat': Schema.string(description: 'Branch repo tbchat'),
          'database': Schema.string(description: 'Branch repo database'),
          'im': Schema.string(description: 'Branch module Instant Message'),
          'wallet': Schema.string(description: 'Branch module Wallet'),
          'cloud_storage': Schema.string(
            description: 'Branch module Cloud Storage',
          ),
          'socialfi': Schema.string(description: 'Branch module Socialfi'),
          'platform': UntitledSingleSelectEnumSchema(
            values: _buildPlatforms,
            description: 'Platform to build (default: android,ios)',
          ),
          'environment': UntitledSingleSelectEnumSchema(
            values: _buildEnvironments,
            description: 'Build environment (default: dev)',
          ),
          'release_notes': Schema.string(description: 'Release notes'),
        },
        required: ['tbchat', 'database'],
      ),
    ),
    (request) async {
      final job = Job.fromJson(
        await client.postJson('/builds', request.arguments ?? const {}),
      );
      return mcpText('### Build queued\n\n${jobToMarkdown(job)}');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_ci_gen',
      description:
          'Generate proto and API docs for socialfi (POST /gen, alias for '
          'ci.gen). Returns a queued/running job.',
      inputSchema: Schema.object(
        properties: {
          'environment': UntitledSingleSelectEnumSchema(
            values: _buildEnvironments,
            description: 'Build environment (default: dev)',
          ),
          'socialfi': Schema.string(
            description:
                'Branch module Socialfi; empty = default per environment',
          ),
        },
      ),
    ),
    (request) async {
      final job = Job.fromJson(
        await client.postJson('/gen', request.arguments ?? const {}),
      );
      return mcpText('### Gen queued\n\n${jobToMarkdown(job)}');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_ci_reposts',
      description:
          'Repost TikTok, YouTube, Facebook or Instagram videos to TBChat SocialFi (POST /reposts, alias for '
          'ci.reposts). Returns a queued/running job.',
      inputSchema: Schema.object(
        properties: {
          'url': Schema.string(
              description:
                  'TikTok, YouTube, Facebook or Instagram video or profile link'),
          'environment': UntitledSingleSelectEnumSchema(
            values: _buildEnvironments,
            description: 'Environment (default: dev)',
          ),
          'limit': Schema.int(
            description: 'Most recent videos to take from a profile, 1-20 '
                '(default 3)',
          ),
        },
        required: ['url'],
      ),
    ),
    (request) async {
      final job = Job.fromJson(
        await client.postJson('/reposts', request.arguments ?? const {}),
      );
      return mcpText('### Reposts queued\n\n${jobToMarkdown(job)}');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_ci_replace',
      description: 'Replace the SDK inside tbchat (POST /replace, alias for '
          'ci.replace). Returns a queued/running job.',
      inputSchema: Schema.object(
        properties: {
          'url': Schema.string(description: 'URL của SDK'),
          'tbchat': Schema.string(description: 'Branch repo tbchat'),
        },
        required: ['url', 'tbchat'],
      ),
    ),
    (request) async {
      final job = Job.fromJson(
        await client.postJson('/replace', request.arguments ?? const {}),
      );
      return mcpText('### Replace queued\n\n${jobToMarkdown(job)}');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_ci_clean',
      description:
          'Clean build artifacts and dependencies (POST /cleans, alias for '
          'ci.clean). Runs `git clean` under the hood — recoverable, but '
          'requires invokeDangerous. Returns a queued/running job.',
      inputSchema: Schema.object(
        properties: {
          'mode': UntitledSingleSelectEnumSchema(
            values: const ['full', 'files'],
            description: 'Empty = same as /cleans with no mode',
          ),
        },
      ),
    ),
    (request) async {
      final job = Job.fromJson(
        await client.postJson('/cleans', request.arguments ?? const {}),
      );
      return mcpText('### Clean queued\n\n${jobToMarkdown(job)}');
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_autocomplete_branches',
      description: 'Get a list of remote Git branches for autocomplete (GET '
          '/autocomplete/branches). Helpful for selecting correct branch '
          'names when triggering builds.',
      inputSchema: Schema.object(
        properties: {
          'repo': UntitledSingleSelectEnumSchema(
            values: _repos,
            description: 'Repository name (default: tbchat)',
          ),
          'query': Schema.string(
              description: 'Filter/search string to match branches'),
        },
      ),
    ),
    (request) async {
      final args = request.arguments ?? const {};
      final query = <String, String>{
        if (args['repo'] case final repo?) 'repo': repo as String,
        if (args['query'] case final q?) 'query': q as String,
      };
      final qs = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
      final json = await client.getJson('/autocomplete/branches$qs');
      final branches = (json['branches'] as List).cast<String>();
      if (branches.isEmpty) return mcpText('_No matching branches._');
      return mcpText(branches.map((branch) => '- `$branch`').join('\n'));
    },
  );
}
