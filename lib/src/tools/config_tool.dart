import 'package:dart_mcp/server.dart';
import 'package:nexsoft_server_shared/nexsoft_server_shared.dart';

import '../config_edits.dart' as edit;
import '../mcp_response.dart';
import '../nexsoft_client.dart';
import '../server.dart';

String? _string(Map<String, Object?>? args, String key) {
  final value = args?[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

bool? _bool(Map<String, Object?>? args, String key) {
  final value = args?[key];
  return value is bool ? value : null;
}

int? _int(Map<String, Object?>? args, String key) {
  final value = args?[key];
  return value is num ? value.toInt() : null;
}

String _hours(WorkHours h) => '${h.start}–${h.end}'
    '${h.lunchStart == null ? '' : ' (lunch ${h.lunchStart}–${h.lunchEnd})'}';

/// The schedule as one readable block: the week, the exceptions and the jobs
/// with when each runs next.
String scheduleToMarkdown(ScheduleInfo info) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final week = [
    for (final rule in info.calendar.weekdays)
      '| ${days[rule.weekday - 1]} | ${rule.working ? 'working' : 'off'} '
          '| ${_hours(rule.hours)} |',
  ];
  final exceptions = info.calendar.exceptions.isEmpty
      ? '_None._'
      : [
          for (final e in info.calendar.exceptions)
            '- `${e.date}` — ${e.working ? 'working day' : 'day off'}'
                '${e.hours == null ? '' : ' ${_hours(e.hours!)}'}'
                '${e.note.isEmpty ? '' : ' · ${e.note}'}',
        ].join('\n');
  final jobs = [
    for (final job in info.jobs)
      '| `${job.config.name}` | ${job.config.kind.name} '
          '| ${job.config.enabled ? 'on' : 'off'} | ${job.rule} '
          '| ${job.nextRun?.toIso8601String() ?? '—'} |',
  ];
  return [
    '**Working week** (server local time)\n\n| Day | | Hours |\n| --- | --- | --- |\n${week.join('\n')}',
    '**Exceptions**\n\n$exceptions',
    '**Jobs**\n\n| Name | Kind | | Rule | Next run |\n| --- | --- | --- | --- | --- |\n${jobs.join('\n')}',
  ].join('\n\n');
}

/// The tools for changing the server's configuration without a deploy: the
/// working calendar and the scheduled jobs, the admin limits, and the
/// project-specific AI prompts.
///
/// Each edit reads the document, changes the one thing asked for and sends it
/// back, so a caller says "make 2 Jan a day off" rather than assembling the
/// whole calendar `schedule.set` takes. The server still validates everything.
void registerConfigTools(NexsoftMcpServer server, NexsoftClient client) {
  Future<CallToolResult> saveSchedule(
    ScheduleInfo current, {
    WorkCalendar? calendar,
    List<ScheduledJobConfig>? jobs,
  }) async {
    final saved = await client.scheduleSet(
      ScheduleSetParams(
        calendar: calendar ?? current.calendar,
        jobs: jobs ?? [for (final job in current.jobs) job.config],
      ),
    );
    return mcpText('✅ Saved.\n\n${scheduleToMarkdown(saved)}');
  }

  // ---- schedule ---------------------------------------------------------

  server.registerTool(
    Tool(
      name: 'nexsoft_schedule_get',
      description:
          'Show the working calendar (which weekdays are worked and their '
          'hours), the days off and make-up days, and every scheduled job '
          'with its rule and next run (schedule.get).',
      inputSchema: Schema.object(),
    ),
    (request) async => mcpText(scheduleToMarkdown(await client.scheduleGet())),
  );

  server.registerTool(
    Tool(
      name: 'nexsoft_schedule_set_weekday',
      description:
          'Change one weekday of the working calendar: whether it is worked '
          'and/or its hours. Only what you give changes. Admin. Times are '
          'HH:mm in the server\'s local time.',
      inputSchema: Schema.object(
        properties: {
          'weekday': Schema.string(
            description: '1 (Monday) to 7 (Sunday), or a name like "sat"',
          ),
          'working': Schema.bool(description: 'Work this weekday or not'),
          'start': Schema.string(description: 'Start of the day, HH:mm'),
          'end': Schema.string(description: 'End of the day, HH:mm'),
          'lunch_start': Schema.string(description: 'Lunch starts, HH:mm'),
          'lunch_end': Schema.string(description: 'Lunch ends, HH:mm'),
          'no_lunch': Schema.bool(description: 'Remove the lunch break'),
        },
        required: ['weekday'],
      ),
    ),
    (request) async {
      final args = request.arguments;
      final current = await client.scheduleGet();
      return saveSchedule(
        current,
        calendar: edit.editWeekday(
          current.calendar,
          weekday: edit.parseWeekday(_string(args, 'weekday') ?? ''),
          working: _bool(args, 'working'),
          start: _string(args, 'start'),
          end: _string(args, 'end'),
          lunchStart: _string(args, 'lunch_start'),
          lunchEnd: _string(args, 'lunch_end'),
          noLunch: _bool(args, 'no_lunch') ?? false,
        ),
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'nexsoft_schedule_add_exception',
      description:
          'Declare a day off (a holiday, working=false) or a make-up working '
          'day (working=true) on a date, replacing any already there. A '
          'working day may carry its own hours; otherwise it uses its '
          'weekday\'s. Jobs pinned to the working day then follow it. Admin.',
      inputSchema: Schema.object(
        properties: {
          'date': Schema.string(description: 'yyyy-MM-dd'),
          'working': Schema.bool(
            description: 'false = day off, true = make-up working day',
          ),
          'note': Schema.string(
            description: 'What it is for, e.g. "National Day"',
          ),
          'start': Schema.string(description: 'Working day only: start, HH:mm'),
          'end': Schema.string(description: 'Working day only: end, HH:mm'),
          'lunch_start': Schema.string(description: 'Working day only'),
          'lunch_end': Schema.string(description: 'Working day only'),
        },
        required: ['date', 'working'],
      ),
    ),
    (request) async {
      final args = request.arguments;
      final current = await client.scheduleGet();
      return saveSchedule(
        current,
        calendar: edit.addException(
          current.calendar,
          date: _string(args, 'date') ?? '',
          working: _bool(args, 'working') ?? false,
          note: _string(args, 'note') ?? '',
          start: _string(args, 'start'),
          end: _string(args, 'end'),
          lunchStart: _string(args, 'lunch_start'),
          lunchEnd: _string(args, 'lunch_end'),
        ),
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'nexsoft_schedule_remove_exception',
      description: 'Remove the day off or make-up day on a date. Admin.',
      inputSchema: Schema.object(
        properties: {'date': Schema.string(description: 'yyyy-MM-dd')},
        required: ['date'],
      ),
    ),
    (request) async {
      final current = await client.scheduleGet();
      return saveSchedule(
        current,
        calendar: edit.removeException(
          current.calendar,
          _string(request.arguments, 'date') ?? '',
        ),
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'nexsoft_schedule_set_job',
      description:
          'Change a scheduled job — switch it on or off, move it — or add a '
          'spoken announcement (a new name needs timing, prompt and '
          'fallback). Timing is either `anchor` (+ `offset_minutes`) to follow '
          'the working day, or `time` for every day at a fixed HH:mm. Only '
          'what you give changes. Admin.',
      inputSchema: Schema.object(
        properties: {
          'name': Schema.string(
            description: 'Job name, e.g. LunchReminderJob, or a new one',
          ),
          'enabled': Schema.bool(description: 'Run it or not'),
          'anchor': Schema.string(
            description:
                'work_start | work_end | lunch_start | lunch_end — the point of '
                'the working day it runs at',
          ),
          'offset_minutes': Schema.int(
            description: 'Minutes after the anchor (negative = before)',
          ),
          'time': Schema.string(
            description: 'HH:mm: run every day at this time instead',
          ),
          'prompt': Schema.string(
            description: 'Announcement only: what the AI is asked to say',
          ),
          'fallback': Schema.string(
            description: 'Announcement only: spoken if the AI cannot answer',
          ),
        },
        required: ['name'],
      ),
    ),
    (request) async {
      final args = request.arguments;
      final current = await client.scheduleGet();
      final anchor = _string(args, 'anchor');
      return saveSchedule(
        current,
        jobs: edit.editJob(
          [for (final job in current.jobs) job.config],
          name: _string(args, 'name') ?? '',
          enabled: _bool(args, 'enabled'),
          anchor: anchor == null ? null : edit.parseAnchor(anchor),
          offsetMinutes: _int(args, 'offset_minutes'),
          time: _string(args, 'time'),
          prompt: _string(args, 'prompt'),
          fallback: _string(args, 'fallback'),
        ),
      );
    },
  );

  server.registerTool(
    Tool(
      name: 'nexsoft_schedule_remove_job',
      description:
          'Delete a spoken announcement. The built-in jobs cannot be deleted, '
          'only switched off with nexsoft_schedule_set_job enabled=false. Admin.',
      inputSchema: Schema.object(
        properties: {'name': Schema.string(description: 'Announcement name')},
        required: ['name'],
      ),
    ),
    (request) async {
      final current = await client.scheduleGet();
      return saveSchedule(
        current,
        jobs: edit.removeJob(
          [for (final job in current.jobs) job.config],
          _string(request.arguments, 'name') ?? '',
        ),
      );
    },
  );

  // ---- limits -----------------------------------------------------------

  String limitsToMarkdown(AppLimits limits) {
    final json = limits.toJson();
    return [
      '| Limit | Value | Allowed |',
      '| --- | ---: | --- |',
      for (final entry in AppLimits.ranges.entries)
        '| `${entry.key}` | ${json[entry.key]} '
            '| ${entry.value.min}–${entry.value.max} |',
    ].join('\n');
  }

  server.registerTool(
    Tool(
      name: 'nexsoft_limits_get',
      description:
          'Show the limits an admin can change — history retention, build '
          'timeout, daily-report sweep, review and AI settings — with the '
          'range each allows (limits.get).',
      inputSchema: Schema.object(),
    ),
    (request) async =>
        mcpText(limitsToMarkdown((await client.limitsGet()).limits)),
  );

  server.registerTool(
    Tool(
      name: 'nexsoft_limits_set',
      description:
          'Change one or more limits; the ones you name change and the rest '
          'keep their value. Applies from the next use, no restart '
          '(limits.set). Admin. See nexsoft_limits_get for names and ranges.',
      inputSchema: Schema.object(
        properties: {
          for (final key in AppLimits.ranges.keys)
            key: Schema.int(
              minimum: AppLimits.ranges[key]!.min,
              maximum: AppLimits.ranges[key]!.max,
            ),
        },
      ),
    ),
    (request) async {
      final named = <String, Object?>{
        for (final key in AppLimits.ranges.keys)
          if (request.arguments?[key] is num)
            key: (request.arguments![key] as num).toInt(),
      };
      if (named.isEmpty) {
        throw NexsoftRequestError(
            400, 'config.invalid_edit', 'Name at least one limit.');
      }
      final saved = await client.limitsSet(
        LimitsSetParams(
          limits: AppLimits.fromJson({
            ...(await client.limitsGet()).limits.toJson(),
            ...named,
          }),
        ),
      );
      return mcpText('✅ Saved.\n\n${limitsToMarkdown(saved.limits)}');
    },
  );

  // ---- AI provider ------------------------------------------------------

  String providerToMarkdown(AiProviderInfo info) =>
      '- **Active provider**: `${info.provider}`\n'
      '- **Available** (have API keys): ${info.available.map((p) => '`$p`').join(', ')}\n'
      '- **Failover to the other provider**: ${info.failover ? 'on' : 'off'}\n'
      '- **Models** (Flash / Pro): '
      'gemini `${info.models.geminiFlash}` / `${info.models.geminiPro}`, '
      'groq `${info.models.groqFlash}` / `${info.models.groqPro}`';

  server.registerTool(
    Tool(
      name: 'nexsoft_ai_provider_get',
      description:
          'Show which AI provider (gemini or groq) serves reviews, translations '
          'and announcements, which have API keys, and whether the other takes '
          'over when the active one is down (admin.aiProvider.get).',
      inputSchema: Schema.object(),
    ),
    (request) async =>
        mcpText(providerToMarkdown(await client.aiProviderGet())),
  );

  server.registerTool(
    Tool(
      name: 'nexsoft_ai_provider_set',
      description:
          'Select the AI provider, turn failover on or off, and/or set the model '
          'id a provider uses for the flash or pro tier. The provider must '
          'have an API key configured. Applies to the next request, no restart '
          '(admin.aiProvider.set). Admin.',
      inputSchema: Schema.object(
        properties: {
          'provider': Schema.string(description: 'gemini or groq'),
          'failover': Schema.bool(
            description: 'Try the other provider when the active one is down',
          ),
          'gemini_flash': Schema.string(description: 'Gemini model id, flash'),
          'gemini_pro': Schema.string(description: 'Gemini model id, pro'),
          'groq_flash': Schema.string(description: 'Groq model id, flash'),
          'groq_pro': Schema.string(description: 'Groq model id, pro'),
        },
      ),
    ),
    (request) async {
      final provider = _string(request.arguments, 'provider');
      final failover = _bool(request.arguments, 'failover');
      final geminiFlash = _string(request.arguments, 'gemini_flash');
      final geminiPro = _string(request.arguments, 'gemini_pro');
      final groqFlash = _string(request.arguments, 'groq_flash');
      final groqPro = _string(request.arguments, 'groq_pro');
      if (provider == null &&
          failover == null &&
          geminiFlash == null &&
          geminiPro == null &&
          groqFlash == null &&
          groqPro == null) {
        throw NexsoftRequestError(
          400,
          'config.invalid_edit',
          'Give a provider, failover, or a model id.',
        );
      }
      // The server takes the provider on every call; keep the current one when
      // only failover is being changed.
      final current = provider ?? (await client.aiProviderGet()).provider;
      final saved = await client.aiProviderSet(
        AiProviderSetParams(
          provider: current,
          failover: failover,
          geminiFlash: geminiFlash,
          geminiPro: geminiPro,
          groqFlash: groqFlash,
          groqPro: groqPro,
        ),
      );
      return mcpText('✅ Saved.\n\n${providerToMarkdown(saved)}');
    },
  );
}
