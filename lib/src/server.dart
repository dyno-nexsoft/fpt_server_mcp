import 'dart:async';

import 'package:dart_mcp/server.dart';

import 'fpt_client.dart';
import 'markdown.dart';
import 'tools/action_tool.dart';
import 'tools/admin_tool.dart';
import 'tools/build_tool.dart';
import 'tools/config_tool.dart';
import 'tools/job_tool.dart';
import 'tools/meta_tool.dart';
import 'tools/zentao_tool.dart';

/// Kept in sync with `pubspec.yaml`'s `version:` by hand — this process has
/// no bundled `package.json`-equivalent to read its own version from at
/// runtime.
const mcpServerVersion = '3.5.0';

/// fpt_server's MCP server: a thin, discoverable wrapper over its REST API
/// (`docs/rest-api.md` in the fpt_server repo). Every tool is a direct
/// mapping to one REST endpoint or action — no business logic lives here.
base class FptMcpServer extends MCPServer with ToolsSupport {
  FptMcpServer(super.channel, {FptClient? client})
      : client = client ?? FptClient(),
        super.fromStreamChannel(
          implementation: Implementation(
            name: 'fpt_server MCP Server',
            version: mcpServerVersion,
          ),
        ) {
    registerMetaTools(this, this.client);
    registerJobTools(this, this.client);
    registerBuildTools(this, this.client);
    registerZentaoTools(this, this.client);
    registerAdminTools(this, this.client);
    registerConfigTools(this, this.client);
    registerActionTools(this, this.client);
  }

  final FptClient client;

  /// Every tool runs inside a guard: a failure comes back as an error result
  /// with a short Markdown message rather than escaping as an exception whose
  /// stack trace becomes the tool's output.
  @override
  void registerTool(
    Tool tool,
    FutureOr<CallToolResult> Function(CallToolRequest) impl, {
    bool validateArguments = true,
  }) =>
      super.registerTool(tool, (request) async {
        try {
          return await impl(request);
        } catch (error) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: errorToMarkdown(error))],
          );
        }
      }, validateArguments: validateArguments);
}
