import 'package:dart_mcp/server.dart';
import 'package:fpt_server_shared/fpt_server_shared.dart';

import '../config_edits.dart' as edit;
import '../fpt_client.dart';
import '../mcp_response.dart';
import '../server.dart';

/// Lets the typed `FptActions` calls run over the MCP client's plain POST.
class _Transport implements ActionTransport {
  const _Transport(this._client);

  final FptClient _client;

  @override
  Future<Map<String, dynamic>> invokeAction(
    String name,
    Map<String, Object?> params,
  ) =>
      _client.postJson('/actions/$name', params);
}

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
void registerConfigTools(FptMcpServer server, FptClient client) {
  final api = _Transport(client);

  Future<CallToolResult> saveSchedule(
    ScheduleInfo current, {
    WorkCalendar? calendar,
    List<ScheduledJobConfig>? jobs,
  }) async {
    final saved = await api.scheduleSet(
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
      name: 'fpt_schedule_get',
      description:
          'Show the working calendar (which weekdays are worked and their '
          'hours), the days off and make-up days, and every scheduled job '
          'with its rule and next run (schedule.get).',
      inputSchema: Schema.object(),
    ),
    (request) async => mcpText(scheduleToMarkdown(await api.scheduleGet())),
  );

  server.registerTool(
    Tool(
      name: 'fpt_schedule_set_weekday',
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
      final current = await api.scheduleGet();
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
      name: 'fpt_schedule_add_exception',
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
      final current = await api.scheduleGet();
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
      name: 'fpt_schedule_remove_exception',
      description: 'Remove the day off or make-up day on a date. Admin.',
      inputSchema: Schema.object(
        properties: {'date': Schema.string(description: 'yyyy-MM-dd')},
        required: ['date'],
      ),
    ),
    (request) async {
      final current = await api.scheduleGet();
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
      name: 'fpt_schedule_set_job',
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
      final current = await api.scheduleGet();
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
      name: 'fpt_schedule_remove_job',
      description:
          'Delete a spoken announcement. The built-in jobs cannot be deleted, '
          'only switched off with fpt_schedule_set_job enabled=false. Admin.',
      inputSchema: Schema.object(
        properties: {'name': Schema.string(description: 'Announcement name')},
        required: ['name'],
      ),
    ),
    (request) async {
      final current = await api.scheduleGet();
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
      name: 'fpt_limits_get',
      description:
          'Show the limits an admin can change — history retention, build '
          'timeout, daily-report sweep, review and AI settings — with the '
          'range each allows (limits.get).',
      inputSchema: Schema.object(),
    ),
    (request) async =>
        mcpText(limitsToMarkdown((await api.limitsGet()).limits)),
  );

  server.registerTool(
    Tool(
      name: 'fpt_limits_set',
      description:
          'Change one or more limits; the ones you name change and the rest '
          'keep their value. Applies from the next use, no restart '
          '(limits.set). Admin. See fpt_limits_get for names and ranges.',
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
        throw FptRequestError(
            400, 'config.invalid_edit', 'Name at least one limit.');
      }
      final saved = await api.limitsSet(
        LimitsSetParams(
          limits: AppLimits.fromJson({
            ...(await api.limitsGet()).limits.toJson(),
            ...named,
          }),
        ),
      );
      return mcpText('✅ Saved.\n\n${limitsToMarkdown(saved.limits)}');
    },
  );

  // ---- prompts ----------------------------------------------------------

  server.registerTool(
    Tool(
      name: 'fpt_prompts_get',
      description:
          'Show the editable parts of the AI review and translation prompts '
          '(review_intro, review_conventions, translator_intro) and the '
          'built-in text they reset to (prompts.get).',
      inputSchema: Schema.object(),
    ),
    (request) async {
      final info = await api.promptsGet();
      final p = info.prompts.toJson();
      final d = info.defaults.toJson();
      return mcpText([
        for (final key in p.keys)
          '**$key**${p[key] == d[key] ? ' _(built-in)_' : ' _(edited)_'}\n\n'
              '```\n${p[key]}\n```',
      ].join('\n\n'));
    },
  );

  server.registerTool(
    Tool(
      name: 'fpt_prompts_set',
      description:
          'Change the project parts of the AI prompts; the fields you name '
          'change and the rest keep their text. Applies to the next review or '
          'translation (prompts.set). Admin. Use fpt_prompts_get first to see '
          'the current text; to reset a field, pass the built-in text.',
      inputSchema: Schema.object(
        properties: {
          'review_intro': Schema.string(
            description: 'Who the reviewer is and what the project is',
          ),
          'review_conventions': Schema.string(
            description: 'The conventions the review checks, a Markdown list',
          ),
          'translator_intro': Schema.string(
            description: 'What app the translated strings are for',
          ),
        },
      ),
    ),
    (request) async {
      final named = <String, Object?>{
        for (final key in const [
          'review_intro',
          'review_conventions',
          'translator_intro',
        ])
          if (_string(request.arguments, key) case final value?) key: value,
      };
      if (named.isEmpty) {
        throw FptRequestError(
            400, 'config.invalid_edit', 'Name at least one prompt field.');
      }
      final current = (await api.promptsGet()).prompts;
      final saved = await api.promptsSet(
        AiPromptsSetParams(
          prompts: AiPrompts.fromJson({...current.toJson(), ...named}),
        ),
      );
      return mcpText(
        '✅ Saved ${named.keys.join(', ')}.\n\n'
        '${saved.prompts.problems().isEmpty ? '' : 'Problems: ${saved.prompts.problems().join(' ')}'}',
      );
    },
  );
}
