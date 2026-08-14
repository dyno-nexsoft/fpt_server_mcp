import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:fpt_server_mcp/src/server.dart';

void main() {
  FptMcpServer(stdioChannel(input: io.stdin, output: io.stdout));
  io.stderr.writeln('fpt_server MCP Server started via stdio.');
}
