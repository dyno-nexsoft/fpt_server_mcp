/** Build a standard MCP text-only content response. */
export function mcpText(text: string) {
  return { content: [{ type: 'text' as const, text }] };
}

/** Build an MCP error content response (`isError: true`) from a caught error. */
export function mcpError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return { content: [{ type: 'text' as const, text: message }], isError: true };
}
