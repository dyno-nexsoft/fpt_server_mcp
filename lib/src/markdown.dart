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

/// `admin.logs.tail`: the lines as a code block, ready to read or paste.
String logLinesToMarkdown(Map<String, dynamic> json) {
  final lines = [
    for (final line in json['lines'] as List<dynamic>? ?? const [])
      if ('$line'.isNotEmpty) '$line',
  ];
  if (lines.isEmpty) return '_The log is empty._';
  return _codeBlock(lines);
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
