import 'dart:io';

import 'package:fpt_server_shared/fpt_server_shared.dart';
import 'package:http/http.dart' as http;

import 'fpt_client.dart';

/// Renders an action's JSON result as Markdown a person (or a model) can read
/// at a glance, instead of pretty-printed JSON.
///
/// Works for any shape, so a tool with no dedicated formatter still reads well:
/// the `message` (if any) leads, plain fields become a bullet list, a list of
/// objects becomes a table, a nested object a sub-list, and a long list of
/// strings (a log, say) a code block.
String resultToMarkdown(Map<String, dynamic> json) {
  final message = json['message'];
  final blocks = <String>[
    if (message is String && message.isNotEmpty) message,
  ];

  final bullets = <String>[];
  final sections = <String>[];
  for (final entry in json.entries) {
    if (entry.key == 'message') continue;
    final value = entry.value;
    if (value == null) continue;
    switch (value) {
      case List<dynamic> list when list.isNotEmpty && list.every(_isMap):
        sections.add('**${entry.key}**\n\n${_table(list.cast<Map>())}');
      case List<dynamic> list when _isInline(list):
        bullets.add('- **${entry.key}**: ${list.join(', ')}');
      case List<dynamic> list when list.isNotEmpty:
        sections.add(
            '**${entry.key}**\n\n${_codeBlock([for (final e in list) '$e'])}');
      case List<dynamic>():
        bullets.add('- **${entry.key}**: _none_');
      case Map<String, dynamic> map:
        sections.add('**${entry.key}**\n\n${_nested(map)}');
      case String text when text.contains('\n'):
        sections.add('**${entry.key}**\n\n${_codeBlock(text.split('\n'))}');
      default:
        bullets.add('- **${entry.key}**: $value');
    }
  }
  if (bullets.isNotEmpty) blocks.add(bullets.join('\n'));
  blocks.addAll(sections);
  return blocks.isEmpty ? '_Done._' : blocks.join('\n\n');
}

/// `admin.apiKeys.list` as a table — one row per key, the hash left out (64
/// characters nobody reads) and the key this call was made with marked.
String apiKeysToMarkdown(Map<String, dynamic> json) {
  final keys = [
    for (final key in json['keys'] as List<dynamic>? ?? const [])
      ApiKeyInfo.fromJson(key as Map<String, dynamic>),
  ];
  if (keys.isEmpty) return '_No API keys._';
  final current = json['current_key_id'];
  final rows = [
    for (final key in keys)
      '| ${_cell(key.name)}${key.id == current ? ' _(this key)_' : ''} '
          '| `${key.id}` '
          '| ${_cell(key.scopes.join(', '))} '
          '| ${_cell(key.discord?.label ?? key.discordUserId ?? '—')} '
          '| ${key.lastUsedAt?.toIso8601String() ?? 'never'} |',
  ];
  return '| Name | Id | Scopes | Discord | Last used |\n'
      '| --- | --- | --- | --- | --- |\n${rows.join('\n')}';
}

/// `admin.apiKeys.add`, with the secret set apart: it is shown exactly once
/// and is the one thing the reader has to act on.
String apiKeyCreatedToMarkdown(Map<String, dynamic> json) {
  final secret = json['secret'];
  if (secret is! String) return resultToMarkdown(json);
  final scopes = json['scopes'];
  return [
    '### API key created',
    [
      '- **id**: `${json['id']}`',
      '- **name**: ${json['name']}',
      if (scopes is List) '- **scopes**: ${scopes.join(', ')}',
    ].join('\n'),
    'Secret (shown once — copy it now): `$secret`',
  ].join('\n\n');
}

/// What a log read may put in front of the reader, in characters — about 4k
/// tokens. `server.log` is mostly one audit line per dashboard poll, and an
/// unbounded tail of it overflowed the tool-result limit before the
/// interesting lines were even reached.
const logTailMaxChars = 12000;

/// `admin.logs.tail`: the lines as a code block, ready to read or paste.
///
/// When the reply carries `first_line`, every line is prefixed with its
/// absolute number and a header gives the range and the log's length — the
/// numbers a later `from_line`/`to_line` call means.
///
/// [contains] keeps only the lines holding that text (case-insensitive) —
/// the way to find one thing in a log that is mostly polling — and [limit]
/// then caps how many of the newest remain. Whatever is still over
/// [maxChars] loses its *oldest* lines, with a note saying how many, so the
/// reader knows the top of the block is not the start of the log.
String logLinesToMarkdown(
  Map<String, dynamic> json, {
  String? contains,
  int limit = 100,
  int maxChars = logTailMaxChars,
}) {
  final needle = contains?.trim().toLowerCase();
  final firstLine = (json['first_line'] as num?)?.toInt();
  final totalLines = (json['total_lines'] as num?)?.toInt();
  final raw = json['lines'] as List<dynamic>? ?? const [];

  // (number, text) — numbered before filtering, so a filtered line keeps
  // the number it has in the file.
  var entries = [
    for (var i = 0; i < raw.length; i++)
      if ('${raw[i]}'.isNotEmpty &&
          (needle == null ||
              needle.isEmpty ||
              '${raw[i]}'.toLowerCase().contains(needle)))
        (firstLine == null ? null : firstLine + i, '${raw[i]}'),
  ];
  if (entries.isEmpty) {
    return needle == null || needle.isEmpty
        ? (raw.isEmpty && firstLine != null && totalLines != null
            ? '_No lines there — the log has $totalLines._'
            : '_The log is empty._')
        : '_No recent log line contains `$contains`._';
  }
  if (entries.length > limit) {
    entries = entries.sublist(entries.length - limit);
  }

  final width = entries.last.$1?.toString().length ?? 0;
  final rendered = [
    for (final (number, text) in entries)
      number == null ? text : '${number.toString().padLeft(width)}  $text',
  ];

  var total = 0;
  var keepFrom = rendered.length;
  while (
      keepFrom > 0 && total + rendered[keepFrom - 1].length + 1 <= maxChars) {
    keepFrom--;
    total += rendered[keepFrom].length + 1;
  }
  // A single line longer than the whole budget still shows, cut short,
  // rather than an empty block.
  if (keepFrom == rendered.length) {
    return _codeBlock([rendered.last.substring(0, maxChars)]);
  }

  final shown = entries.sublist(keepFrom);
  final notes = [
    if (shown.first.$1 != null && totalLines != null)
      'Lines ${shown.first.$1}–${shown.last.$1} of $totalLines.',
    if (keepFrom > 0)
      '$keepFrom older line(s) left out to stay under $maxChars characters — '
          'ask for fewer `lines`, a narrower range, or filter with `contains`.',
  ];
  final block = _codeBlock(rendered.sublist(keepFrom));
  return notes.isEmpty ? block : '_${notes.join(' ')}_\n\n$block';
}

/// A tool failure as one short Markdown message, in place of the raw exception
/// and stack trace an uncaught error would put in front of the reader.
String errorToMarkdown(Object error) => switch (error) {
      FptRequestError(:final status, :final code, :final message) =>
        '**Request failed** ($status `$code`): $message',
      http.ClientException() ||
      SocketException() =>
        '**Cannot reach the fpt_server API.** It may be restarting — try again in '
            'a moment.\n\n_${_firstLine('$error')}_',
      _ => '**Unexpected error**: ${_firstLine('$error')}',
    };

bool _isMap(Object? value) => value is Map;

/// A list short enough to read as one comma-separated line.
bool _isInline(List<dynamic> list) =>
    list.isNotEmpty &&
    list.length <= 5 &&
    list.every((e) => e is! Map && e is! List && !'$e'.contains('\n')) &&
    list.join(', ').length <= 80;

String _nested(Map<String, dynamic> map) => [
      for (final entry in map.entries)
        if (entry.value != null) '- **${entry.key}**: ${_inline(entry.value)}',
    ].join('\n');

String _inline(Object? value) => switch (value) {
      List<dynamic>() => value.join(', '),
      Map<dynamic, dynamic>() =>
        value.entries.map((e) => '${e.key}: ${e.value}').join(', '),
      _ => '$value',
    };

String _table(List<Map<dynamic, dynamic>> rows) {
  final columns = <String>[];
  for (final row in rows) {
    for (final key in row.keys) {
      if ('$key' case final name when !columns.contains(name)) {
        columns.add(name);
      }
    }
  }
  final header = '| ${columns.join(' | ')} |';
  final divider = '| ${columns.map((_) => '---').join(' | ')} |';
  final body = [
    for (final row in rows)
      '| ${columns.map((column) => _cell(_inline(row[column]))).join(' | ')} |',
  ];
  return [header, divider, ...body].join('\n');
}

/// A table cell: one line, no pipes, and not longer than a row can bear.
String _cell(String text) {
  final flat = text.replaceAll('\n', ' ').replaceAll('|', r'\|').trim();
  final shown = flat.length > 120 ? '${flat.substring(0, 119)}…' : flat;
  return shown.isEmpty ? '—' : shown;
}

String _codeBlock(List<String> lines) => '```\n${lines.join('\n')}\n```';

String _firstLine(String text) {
  final line = text.split('\n').first.trim();
  return line.length > 200 ? '${line.substring(0, 199)}…' : line;
}
