import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:nexsoft_server_mcp/nexsoft_server_mcp.dart';

void main() {
  NexsoftMcpServer(stdioChannel(input: io.stdin, output: io.stdout));
  io.stderr.writeln('nexsoft_server MCP Server started via stdio.');
}
