import 'dart:io';

import 'package:fpt_server_mcp/src/fpt_client.dart';
import 'package:fpt_server_mcp/src/markdown.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('resultToMarkdown', () {
    test('leads with the message, then lists the plain fields', () {
      expect(
        resultToMarkdown({'message': 'Announced "x"', 'id': 'n-1', 'ok': true}),
        'Announced "x"\n\n- **id**: n-1\n- **ok**: true',
      );
    });

    test('an empty result still says something', () {
      expect(resultToMarkdown({}), '_Done._');
    });

    test('a list of objects becomes a table', () {
      final out = resultToMarkdown({
        'notifications': [
          {'id': 'n-1', 'title': 'A', 'read': false},
          {'id': 'n-2', 'title': 'B|C', 'read': true},
        ],
        'unread_count': 1,
      });
      expect(out, contains('- **unread_count**: 1'));
      expect(out, contains('| id | title | read |'));
      expect(out, contains('| n-1 | A | false |'));
      // A pipe inside a cell must not split it.
      expect(out, contains(r'| n-2 | B\|C | true |'));
    });

    test('a short list of scalars reads inline, a long one as a block', () {
      expect(
        resultToMarkdown({
          'scopes': ['read', 'invoke']
        }),
        '- **scopes**: read, invoke',
      );
      final lines = [for (var i = 0; i < 8; i++) 'line $i'];
      final out = resultToMarkdown({'lines': lines});
      expect(out, startsWith('**lines**\n\n```\nline 0'));
      expect(out, endsWith('line 7\n```'));
    });

    test('a nested object becomes a sub-list, and null fields vanish', () {
      final out = resultToMarkdown({
        'discord': {'username': 'dyno', 'avatar': null},
        'gone': null,
      });
      expect(out, '**discord**\n\n- **username**: dyno');
    });

    test('a multi-line string goes in a code block', () {
      expect(
        resultToMarkdown({'description': 'a\nb'}),
        '**description**\n\n```\na\nb\n```',
      );
    });
  });

  group('apiKeysToMarkdown', () {
    test('one row per key, the current one marked, no hash', () {
      final out = apiKeysToMarkdown({
        'current_key_id': 'k1',
        'keys': [
          {
            'id': 'k1',
            'name': 'Me',
            'key_hash': 'deadbeef',
            'scopes': ['admin'],
            'discord_user_id': '42',
            'discord': {'username': 'dyno'},
          },
          {
            'id': 'k2',
            'name': 'Bot',
            'key_hash': 'cafe',
            'scopes': ['read', 'invoke'],
          },
        ],
      });
      expect(
          out, contains('| Me _(this key)_ | `k1` | admin | dyno | never |'));
      expect(out, contains('| Bot | `k2` | read, invoke | — | never |'));
      expect(out, isNot(contains('deadbeef')));
    });

    test('no keys', () {
      expect(apiKeysToMarkdown({'keys': []}), '_No API keys._');
    });
  });

  test('a created key shows its secret apart, once', () {
    final out = apiKeyCreatedToMarkdown({
      'id': 'k9',
      'name': 'New',
      'scopes': ['read'],
      'secret': 's3cret',
    });
    expect(out, contains('### API key created'));
    expect(out, contains('Secret (shown once — copy it now): `s3cret`'));
  });

  group('logLinesToMarkdown', () {
    test('lines as a code block, blanks dropped', () {
      expect(
        logLinesToMarkdown({
          'lines': ['a', '', 'b'],
        }),
        '```\na\nb\n```',
      );
    });

    test('an empty log', () {
      expect(logLinesToMarkdown({'lines': []}), '_The log is empty._');
    });
  });

  group('errorToMarkdown', () {
    test('an API error names its status and code', () {
      expect(
        errorToMarkdown(FptRequestError(409, 'job.finished', 'Already done')),
        '**Request failed** (409 `job.finished`): Already done',
      );
    });

    test('an unreachable server is explained, not dumped', () {
      final out = errorToMarkdown(
        http.ClientException(
          'SocketException: The remote computer refused the connection',
        ),
      );
      expect(out, startsWith('**Cannot reach the fpt_server API.**'));
      expect(out, isNot(contains('#0')));
      expect(
        errorToMarkdown(const SocketException('refused')),
        startsWith('**Cannot reach'),
      );
    });

    test('anything else is one line, without a stack trace', () {
      final out = errorToMarkdown(StateError('boom\n#0 frame'));
      expect(out, '**Unexpected error**: Bad state: boom');
    });
  });
}
