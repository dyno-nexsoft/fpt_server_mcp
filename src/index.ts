#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { registerTools } from './tools.js';
import * as dotenv from 'dotenv';
import { readFileSync } from 'fs';

dotenv.config();

const pkg = JSON.parse(
  readFileSync(new URL('../package.json', import.meta.url), 'utf8')
);

const server = new McpServer({
  name: 'fpt_server MCP Server',
  version: pkg.version,
});

registerTools(server);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('fpt_server MCP Server started via stdio.');
}

main().catch((error) => {
  console.error('Fatal error starting server:', error);
  process.exit(1);
});
