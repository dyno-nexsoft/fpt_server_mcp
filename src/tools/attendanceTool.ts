import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { FptServerClient } from '../fptClient.js';
import { mcpText } from '../utils/mcpResponse.js';

const CHECKIN_TIMES = ['09:00', '09:10', '09:15', '09:20', '09:30'] as const;

/** Registers the `attendance.*` action group's tools. */
export function registerAttendanceTools(server: McpServer, client: FptServerClient): void {
  server.registerTool(
    'fpt_attendance_status',
    {
      description: "View today's attendance subscription and check-in status (attendance.status).",
      inputSchema: {},
    },
    async () => {
      const result = await client.post<{
        subscribed: boolean;
        date: string;
        check_in_time: string | null;
        checkout_notified: boolean;
      }>('/actions/attendance.status', {});
      return mcpText(
        `- **subscribed**: ${result.subscribed}\n` +
          `- **date**: ${result.date}\n` +
          `- **check_in_time**: ${result.check_in_time ?? '_none_'}\n` +
          `- **checkout_notified**: ${result.checkout_notified}`
      );
    }
  );

  server.registerTool(
    'fpt_attendance_checkin',
    {
      description:
        "Record today's check-in time (attendance.checkin). Validated against server time, same rule a Discord " +
        'check-in button enforces.',
      inputSchema: {
        time: z.enum(CHECKIN_TIMES).describe('Check-in time slot'),
      },
    },
    async ({ time }) => {
      const result = await client.post<any>('/actions/attendance.checkin', { time });
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_attendance_subscribe',
    {
      description: 'Subscribe to daily attendance check-in DM reminders (attendance.subscribe).',
      inputSchema: {},
    },
    async () => {
      const result = await client.post<any>('/actions/attendance.subscribe', {});
      return mcpText(JSON.stringify(result, null, 2));
    }
  );

  server.registerTool(
    'fpt_attendance_unsubscribe',
    {
      description: 'Unsubscribe from daily attendance check-in reminders (attendance.unsubscribe).',
      inputSchema: {},
    },
    async () => {
      const result = await client.post<any>('/actions/attendance.unsubscribe', {});
      return mcpText(JSON.stringify(result, null, 2));
    }
  );
}
