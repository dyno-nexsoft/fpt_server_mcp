import 'package:fpt_server_mcp/src/config_edits.dart' as edit;
import 'package:fpt_server_mcp/src/fpt_client.dart';
import 'package:fpt_server_shared/fpt_server_shared.dart';
import 'package:test/test.dart';

ScheduledJobConfig _system(String name, JobKind kind, JobTiming timing) =>
    ScheduledJobConfig(name: name, kind: kind, timing: timing);

void main() {
  final standard = WorkCalendar.standard();
  final jobs = [
    _system(
        'Report', JobKind.dailyReport, JobTiming.workday(TimeAnchor.workStart)),
    _system('Cleanup', JobKind.cleanup, JobTiming.daily(23, 0)),
    ScheduledJobConfig(
      name: 'Lunch',
      kind: JobKind.announcement,
      timing: JobTiming.workday(TimeAnchor.lunchStart),
      prompt: 'p',
      fallback: 'f',
    ),
  ];

  group('parseWeekday', () {
    test('numbers and names', () {
      expect(edit.parseWeekday('1'), 1);
      expect(edit.parseWeekday('Sat'), 6);
      expect(edit.parseWeekday('sunday'), 7);
      expect(() => edit.parseWeekday('8'), throwsA(isA<FptRequestError>()));
      expect(() => edit.parseWeekday('x'), throwsA(isA<FptRequestError>()));
    });
  });

  group('editWeekday', () {
    test('changes only what is given', () {
      final out = edit.editWeekday(standard, weekday: 1, end: '17:30');
      final monday = out.ruleFor(1);
      expect(monday.hours.end, '17:30');
      expect(monday.hours.start, '08:30');
      expect(monday.working, isTrue);
      expect(out.ruleFor(2).hours.end, '18:00');
    });

    test('turns a weekday on, keeping its hours', () {
      final out = edit.editWeekday(standard, weekday: 6, working: true);
      expect(out.ruleFor(6).working, isTrue);
      expect(out.ruleFor(6).hours.end, '12:00');
    });

    test('removes lunch, and refuses lunch with only one end', () {
      final none = edit.editWeekday(standard, weekday: 1, noLunch: true);
      expect(none.ruleFor(1).hours.lunchStart, isNull);
      expect(
        () => edit.editWeekday(none, weekday: 1, lunchStart: '12:00'),
        throwsA(isA<FptRequestError>()),
      );
      final back = edit.editWeekday(
        none,
        weekday: 1,
        lunchStart: '12:00',
        lunchEnd: '13:00',
      );
      expect(back.ruleFor(1).hours.lunchEnd, '13:00');
    });

    test('an invalid result is refused', () {
      expect(
        () => edit.editWeekday(standard, weekday: 1, start: '19:00'),
        throwsA(isA<FptRequestError>()),
      );
    });
  });

  group('exceptions', () {
    test('a holiday and a make-up day', () {
      var out = edit.addException(
        standard,
        date: '2026-10-05',
        working: false,
        note: 'Holiday',
      );
      out = edit.addException(out, date: '2026-10-10', working: true);
      expect(out.planFor(DateTime(2026, 10, 5)), isNull);
      expect(out.planFor(DateTime(2026, 10, 10)), isNotNull);
      expect(out.exceptions.map((e) => e.date), ['2026-10-05', '2026-10-10']);
    });

    test('a make-up day with its own hours', () {
      final out = edit.addException(
        standard,
        date: '2026-10-10',
        working: true,
        start: '09:00',
        end: '16:00',
      );
      expect(out.planFor(DateTime(2026, 10, 10))!.hours.end, '16:00');
    });

    test('a day off cannot have hours; a bad date is refused', () {
      expect(
        () => edit.addException(standard,
            date: '2026-10-05', working: false, end: '12:00'),
        throwsA(isA<FptRequestError>()),
      );
      expect(
        () => edit.addException(standard, date: 'soon', working: false),
        throwsA(isA<FptRequestError>()),
      );
    });

    test('adding on a date replaces, removing needs one to exist', () {
      final first =
          edit.addException(standard, date: '2026-10-05', working: false);
      final second =
          edit.addException(first, date: '2026-10-05', working: true);
      expect(second.exceptions, hasLength(1));
      expect(second.exceptions.single.working, isTrue);
      expect(edit.removeException(second, '2026-10-05').exceptions, isEmpty);
      expect(
        () => edit.removeException(standard, '2026-10-05'),
        throwsA(isA<FptRequestError>()),
      );
    });
  });

  group('editJob', () {
    test('switches a job off without touching the rest', () {
      final out = edit.editJob(jobs, name: 'Lunch', enabled: false);
      expect(out.firstWhere((j) => j.name == 'Lunch').enabled, isFalse);
      expect(out.firstWhere((j) => j.name == 'Lunch').prompt, 'p');
      expect(out, hasLength(3));
    });

    test('moves a job to another anchor, or to a fixed time', () {
      final anchored = edit.editJob(
        jobs,
        name: 'Lunch',
        anchor: TimeAnchor.workEnd,
        offsetMinutes: -30,
      );
      final lunch = anchored.firstWhere((j) => j.name == 'Lunch').timing;
      expect(lunch.anchor, TimeAnchor.workEnd);
      expect(lunch.offsetMinutes, -30);

      final daily = edit.editJob(jobs, name: 'Lunch', time: '11:45');
      expect(daily.firstWhere((j) => j.name == 'Lunch').timing.time, '11:45');
    });

    test('an offset alone adjusts a pinned job and is refused on a daily one',
        () {
      final out = edit.editJob(jobs, name: 'Lunch', offsetMinutes: 10);
      expect(out.firstWhere((j) => j.name == 'Lunch').timing.offsetMinutes, 10);
      expect(
        () => edit.editJob(jobs, name: 'Cleanup', offsetMinutes: 10),
        throwsA(isA<FptRequestError>()),
      );
    });

    test('anchor and time together are refused', () {
      expect(
        () => edit.editJob(jobs,
            name: 'Lunch', anchor: TimeAnchor.workEnd, time: '10:00'),
        throwsA(isA<FptRequestError>()),
      );
    });

    test('a new name adds an announcement, if complete', () {
      final out = edit.editJob(
        jobs,
        name: 'Stretch',
        anchor: TimeAnchor.workStart,
        offsetMinutes: 90,
        prompt: 'Remind everyone to stretch.',
        fallback: 'Time to stretch.',
      );
      expect(out, hasLength(4));
      expect(out.last.name, 'Stretch');
      expect(out.last.kind, JobKind.announcement);
      expect(
        () => edit.editJob(jobs, name: 'Stretch', time: '10:00'),
        throwsA(isA<FptRequestError>()),
      );
    });

    test('a built-in job has no prompt to set', () {
      expect(
        () => edit.editJob(jobs, name: 'Cleanup', prompt: 'x'),
        throwsA(isA<FptRequestError>()),
      );
    });

    test('anchor names', () {
      expect(edit.parseAnchor('lunch_end'), TimeAnchor.lunchEnd);
      expect(() => edit.parseAnchor('noon'), throwsA(isA<FptRequestError>()));
    });
  });

  group('removeJob', () {
    test('removes an announcement but not a built-in job', () {
      expect(edit.removeJob(jobs, 'Lunch'), hasLength(2));
      expect(() => edit.removeJob(jobs, 'Cleanup'),
          throwsA(isA<FptRequestError>()));
      expect(
          () => edit.removeJob(jobs, 'Nope'), throwsA(isA<FptRequestError>()));
    });
  });
}
