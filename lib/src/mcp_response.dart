import 'package:dart_mcp/server.dart';

/// A standard MCP text-only content response.
CallToolResult mcpText(String text) =>
    CallToolResult(content: [TextContent(text: text)]);
