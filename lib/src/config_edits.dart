import 'package:nexsoft_server_shared/nexsoft_server_shared.dart';

import 'nexsoft_client.dart';

/// Pure edits to the working calendar and the scheduled jobs: each takes the
/// document as the server has it and returns the changed one, so a tool can
/// change one thing without the caller assembling — or getting wrong — the
/// whole document `schedule.set` takes.
///
/// A bad edit throws a [NexsoftRequestError] saying what is wrong, which the tool
/// guard renders like any other failed request.

Never _refuse(String message) =>
    throw NexsoftRequestError(400, 'config.invalid_edit', message);

const _weekdayNames = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// 1–7 from `1`…`7` or a weekday name (`mon`, `Monday`).
int parseWeekday(String value) {
  final text = value.trim().toLowerCase();
  final number = int.tryParse(text);
  if (number != null && number >= 1 && number <= 7) return number;
  final index = _weekdayNames.indexWhere(
    (name) => text.length >= 3 && name.startsWith(text),
  );
  if (index == -1) {
    _refuse(
        '"$value" is not a weekday: use 1 (Monday) to 7 (Sunday) or a name.');
  }
  return index + 1;
}

/// Changes one weekday's standing rule: whether it is worked and its hours.
/// Only what is given changes; [noLunch] removes the lunch break.
WorkCalendar editWeekday(
  WorkCalendar calendar, {
  required int weekday,
  bool? working,
  String? start,
  String? end,
  String? lunchStart,
  String? lunchEnd,
  bool noLunch = false,
}) {
  final rule = calendar.ruleFor(weekday);
  final hours = _withHours(
    rule.hours,
    start: start,
    end: end,
    lunchStart: lunchStart,
    lunchEnd: lunchEnd,
    noLunch: noLunch,
  );
  final changed = rule.copyWith(working: working ?? rule.working, hours: hours);
  return _checked(
    calendar.copyWith(
      weekdays: [
        for (final existing in calendar.weekdays)
          if (existing.weekday == weekday) changed else existing,
      ],
    ),
  );
}

WorkHours _withHours(
  WorkHours hours, {
  String? start,
  String? end,
  String? lunchStart,
  String? lunchEnd,
  bool noLunch = false,
}) {
  if (noLunch && (lunchStart != null || lunchEnd != null)) {
    _refuse('no_lunch cannot be combined with lunch times.');
  }
  var result =
      hours.copyWith(start: start ?? hours.start, end: end ?? hours.end);
  if (noLunch) {
    return WorkHours(start: result.start, end: result.end);
  }
  if (lunchStart != null || lunchEnd != null) {
    final from = lunchStart ?? result.lunchStart;
    final to = lunchEnd ?? result.lunchEnd;
    if (from == null || to == null) {
      _refuse('Give both lunch_start and lunch_end to add a lunch break.');
    }
    result = result.copyWith(lunchStart: from, lunchEnd: to);
  }
  return result;
}

/// Adds a day off ([working] false) or a make-up day ([working] true) on
/// [date], replacing any already there. A worked day may carry its own hours;
/// without them it uses its weekday's.
WorkCalendar addException(
  WorkCalendar calendar, {
  required String date,
  required bool working,
  String note = '',
  String? start,
  String? end,
  String? lunchStart,
  String? lunchEnd,
}) {
  final customHours =
      start != null || end != null || lunchStart != null || lunchEnd != null;
  if (!working && customHours) {
    _refuse('A day off has no hours; give hours only for a working day.');
  }
  WorkHours? hours;
  if (customHours) {
    final base = calendar.hoursOn(DateTime.tryParse(date) ?? DateTime(2000));
    hours = _withHours(
      base,
      start: start,
      end: end,
      lunchStart: lunchStart,
      lunchEnd: lunchEnd,
    );
  }
  final others = [
    for (final existing in calendar.exceptions)
      if (existing.date != date) existing,
  ];
  return _checked(
    calendar.copyWith(
      exceptions: [
        ...others,
        CalendarException(
          date: date,
          working: working,
          note: note,
          hours: hours,
        ),
      ]..sort((a, b) => a.date.compareTo(b.date)),
    ),
  );
}

WorkCalendar removeException(WorkCalendar calendar, String date) {
  if (!calendar.exceptions.any((e) => e.date == date)) {
    _refuse('There is no exception on $date.');
  }
  return _checked(
    calendar.copyWith(
      exceptions: [
        for (final existing in calendar.exceptions)
          if (existing.date != date) existing,
      ],
    ),
  );
}

WorkCalendar _checked(WorkCalendar calendar) {
  final problems = calendar.problems();
  if (problems.isNotEmpty) _refuse(problems.join(' '));
  return calendar;
}

/// `work_start` | `work_end` | `lunch_start` | `lunch_end`.
TimeAnchor parseAnchor(String value) {
  const wire = {
    'work_start': TimeAnchor.workStart,
    'work_end': TimeAnchor.workEnd,
    'lunch_start': TimeAnchor.lunchStart,
    'lunch_end': TimeAnchor.lunchEnd,
  };
  final anchor = wire[value.trim().toLowerCase()];
  if (anchor == null) {
    _refuse('anchor must be one of: ${wire.keys.join(', ')}.');
  }
  return anchor;
}

/// Changes one job, or adds an announcement when [name] is new. Only what is
/// given changes. Timing is either [anchor] (+ [offsetMinutes]) for a working-day
/// job or [time] (`HH:mm`) for a daily one — never both.
List<ScheduledJobConfig> editJob(
  List<ScheduledJobConfig> jobs, {
  required String name,
  bool? enabled,
  TimeAnchor? anchor,
  int? offsetMinutes,
  String? time,
  String? prompt,
  String? fallback,
}) {
  if (anchor != null && time != null) {
    _refuse('Give either anchor or time, not both.');
  }
  final existing = jobs.where((job) => job.name == name).firstOrNull;
  final timing = _timingFor(existing?.timing, anchor, offsetMinutes, time);

  final ScheduledJobConfig edited;
  if (existing == null) {
    if (timing == null || prompt == null || fallback == null) {
      _refuse(
        '"$name" is not a job. To add an announcement give its timing '
        '(anchor or time), prompt and fallback.',
      );
    }
    edited = ScheduledJobConfig(
      name: name,
      kind: JobKind.announcement,
      enabled: enabled ?? true,
      timing: timing,
      prompt: prompt,
      fallback: fallback,
    );
  } else {
    if (existing.isSystem && (prompt != null || fallback != null)) {
      _refuse('Only an announcement has a prompt and a fallback.');
    }
    edited = existing.copyWith(
      enabled: enabled ?? existing.enabled,
      timing: timing ?? existing.timing,
      prompt: prompt ?? existing.prompt,
      fallback: fallback ?? existing.fallback,
    );
  }
  return _checkedJobs(
    existing == null
        ? [...jobs, edited]
        : [for (final job in jobs) job.name == name ? edited : job],
  );
}

JobTiming? _timingFor(
  JobTiming? current,
  TimeAnchor? anchor,
  int? offsetMinutes,
  String? time,
) {
  if (time != null) return JobTiming(time: time);
  if (anchor != null) {
    return JobTiming(anchor: anchor, offsetMinutes: offsetMinutes ?? 0);
  }
  if (offsetMinutes != null) {
    if (current?.anchor == null) {
      _refuse(
          'offset_minutes only applies to a job pinned to the working day.');
    }
    return current!.copyWith(offsetMinutes: offsetMinutes);
  }
  return null;
}

/// Removes an announcement; the built-in jobs can only be switched off.
List<ScheduledJobConfig> removeJob(
  List<ScheduledJobConfig> jobs,
  String name,
) {
  final job = jobs.where((j) => j.name == name).firstOrNull;
  if (job == null) _refuse('There is no job "$name".');
  if (job.isSystem) {
    _refuse('"$name" is a built-in job: switch it off with enabled=false.');
  }
  return _checkedJobs([
    for (final existing in jobs)
      if (existing.name != name) existing,
  ]);
}

List<ScheduledJobConfig> _checkedJobs(List<ScheduledJobConfig> jobs) {
  final problems = ScheduledJobConfig.listProblems(jobs);
  if (problems.isNotEmpty) _refuse(problems.join(' '));
  return jobs;
}
