import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexsoft_server_mcp/src/nexsoft_client.dart';
import 'package:nexsoft_server_mcp/src/server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// One request the fake nexsoft_server received: the path it hit and the JSON
/// body it was sent.
typedef _Sent = ({String path, Map<String, dynamic> body});

/// A real [NexsoftMcpServer] over an in-memory channel, talking to a fake REST
/// backend — so a test sees exactly what a tool call puts on the wire and
/// what the caller reads back, with nothing mocked in between.
class _Harness {
  _Harness(this._reply) {
    final toServer = StreamController<String>();
    final toClient = StreamController<String>();
    server = NexsoftMcpServer(
      StreamChannel.withCloseGuarantee(toServer.stream, toClient.sink),
      client: NexsoftClient(
        baseUrl: 'https://example.test',
        apiKey: 'k',
        client: MockClient((request) async {
          final body = request.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(request.body) as Map<String, dynamic>;
          sent.add((path: request.url.path, body: body));
          final (status, json) = _reply(request.url.path);
          // Bytes, not a String: `http.Response` would encode a String as
          // latin1, and the server's replies carry emoji.
          return http.Response.bytes(
            utf8.encode(jsonEncode(json)),
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    connection = _client.connectServer(
      StreamChannel.withCloseGuarantee(toClient.stream, toServer.sink),
    );
  }

  final (int, Map<String, Object?>) Function(String path) _reply;
  final _client = MCPClient(Implementation(name: 'test', version: '0.0.0'));
  late final NexsoftMcpServer server;
  late final ServerConnection connection;
  final sent = <_Sent>[];

  Future<void> start() async {
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: _client.capabilities,
        clientInfo: _client.implementation,
      ),
    );
    connection.notifyInitialized(InitializedNotification());
    await server.initialized;
  }

  Future<CallToolResult> call(String tool, [Map<String, Object?>? args]) =>
      connection.callTool(CallToolRequest(name: tool, arguments: args));

  Future<void> stop() async {
    await _client.shutdown();
    await server.shutdown();
  }
}

String _text(CallToolResult result) =>
    result.content.map((c) => (c as TextContent).text).join('\n');

Future<_Harness> _start(
  (int, Map<String, Object?>) Function(String path) reply,
) async {
  final harness = _Harness(reply);
  addTearDown(harness.stop);
  await harness.start();
  return harness;
}

void main() {
  group('zentao tools', () {
    test('finish sends the typed task id and shows the message', () async {
      final h = await _start((_) => (200, {'message': '✅ Finished'}));
      final result =
          await h.call('nexsoft_zentao_report_finish', {'task_id': 7});

      expect(h.sent.single.path, '/actions/zentao.report.finish');
      expect(h.sent.single.body, {'task_id': 7});
      expect(result.isError, isNot(true));
      expect(_text(result), '✅ Finished');
    });

    test('start sends the description and reports the new task id', () async {
      final h = await _start(
        (_) => (200, {'task_id': 42, 'message': 'Started'}),
      );
      final result = await h.call('nexsoft_zentao_report_start', {
        'description': '- did things',
      });

      expect(h.sent.single.path, '/actions/zentao.report.start');
      expect(h.sent.single.body, {'description': '- did things'});
      expect(_text(result), contains('Started'));
      expect(_text(result), contains('**task_id**: 42'));
    });

    test('edit sends both the task id and the new text', () async {
      final h = await _start((_) => (200, {'message': 'Saved'}));
      await h.call('nexsoft_zentao_report_edit', {
        'task_id': 3,
        'description': 'new',
      });

      expect(h.sent.single.path, '/actions/zentao.report.edit');
      expect(h.sent.single.body, {'task_id': 3, 'description': 'new'});
    });

    test('get renders the parsed task', () async {
      final h = await _start(
        (_) => (
          200,
          {
            'id': 9,
            'name': 'Daily report',
            'description': 'did things',
            'status': 'doing',
            'assignee': 'Someone',
            'last_edited': '2026-01-02T03:04:05.000Z',
            'url': 'https://zentao.example.com/task-9',
          },
        ),
      );
      final result = await h.call('nexsoft_zentao_report_get', {'task_id': 9});

      expect(h.sent.single.body, {'task_id': 9});
      final text = _text(result);
      expect(text, contains('Daily report'));
      expect(text, contains('doing'));
      expect(text, contains('https://zentao.example.com/task-9'));
    });
  });

  group('admin tools', () {
    test('apikeys list renders the typed list as a table', () async {
      final h = await _start(
        (_) => (
          200,
          {
            'current_key_id': 'k1',
            'keys': [
              {
                'id': 'k1',
                'name': 'Me',
                'key_hash': 'deadbeef',
                'scopes': ['admin'],
              },
            ],
          },
        ),
      );
      final result = await h.call('nexsoft_admin_apikeys_list');

      expect(h.sent.single.path, '/actions/admin.apiKeys.list');
      expect(_text(result), contains('| Me _(this key)_ | `k1` | admin |'));
      expect(_text(result), isNot(contains('deadbeef')));
    });

    test('apikeys add sends only the name and shows the secret', () async {
      final h = await _start(
        (_) => (
          200,
          {
            'id': 'k2',
            'name': 'CI',
            'scopes': ['read', 'invoke'],
            'role': 'user',
            'secret': 's3cret',
          },
        ),
      );
      final result = await h.call('nexsoft_admin_apikeys_add', {'name': 'CI'});

      expect(h.sent.single.path, '/actions/admin.apiKeys.add');
      expect(h.sent.single.body, {'name': 'CI'});
      expect(_text(result), contains('`s3cret`'));
      expect(_text(result), contains('read, invoke'));
    });

    test('apikeys remove sends the id', () async {
      final h = await _start((_) => (200, {'message': 'Deleted'}));
      final result = await h.call('nexsoft_admin_apikeys_remove', {'id': 'k1'});

      expect(h.sent.single.path, '/actions/admin.apiKeys.remove');
      expect(h.sent.single.body, {'id': 'k1'});
      expect(_text(result), 'Deleted');
    });

    test('cron run sends the job name', () async {
      final h = await _start((_) => (200, {'message': 'Ran'}));
      await h.call('nexsoft_cron_run', {'job': 'cleanup'});

      expect(h.sent.single.path, '/actions/cron.run');
      expect(h.sent.single.body, {'job': 'cleanup'});
    });

    test('hot reload posts with no params', () async {
      final h = await _start((_) => (200, {'message': 'Reloaded'}));
      final result = await h.call('nexsoft_hot_reload');

      expect(h.sent.single.path, '/actions/system.hotReload');
      expect(h.sent.single.body, isEmpty);
      expect(_text(result), 'Reloaded');
    });

    test('restart passes when_idle through, false by default', () async {
      final h = await _start((_) => (200, {'message': 'Restarting'}));
      await h.call('nexsoft_restart', {'when_idle': true});
      await h.call('nexsoft_restart');

      expect(
          h.sent.map((s) => s.path), everyElement('/actions/system.restart'));
      expect(h.sent[0].body['when_idle'], isTrue);
      expect(h.sent[1].body['when_idle'], isNot(isTrue));
    });

    test('logs tail with a filter scans the wider window', () async {
      final h = await _start(
        (_) => (
          200,
          {
            'lines': ['poll', 'SEVERE boom', 'poll'],
            'first_line': 1,
            'total_lines': 3,
          },
        ),
      );
      final result = await h.call('nexsoft_admin_logs_tail', {
        'contains': 'severe',
        'lines': 5,
      });

      expect(h.sent.single.path, '/actions/admin.logs.tail');
      expect(h.sent.single.body['lines'], 1000);
      expect(_text(result), contains('SEVERE boom'));
      expect(_text(result), isNot(contains('poll')));
    });
  });

  test('ci build forwards every ci.build param, new ones included', () async {
    final h = await _start(
      (_) => (
        200,
        {
          'id': 'j-1',
          'command': 'build.sh',
          'state': 'queued',
          'action_name': 'ci.build',
          'created_at': '2026-01-02T03:04:05.000Z',
        },
      ),
    );
    await h.call('nexsoft_ci_build', {
      'tbchat': 'dev',
      'database': 'dev',
      'build_name': '1.4.2',
      'build_number': 42,
      'skip_firebase_distribution': true,
    });

    expect(h.sent.single.path, '/builds');
    expect(h.sent.single.body, containsPair('build_name', '1.4.2'));
    expect(h.sent.single.body, containsPair('build_number', 42));
    expect(
      h.sent.single.body,
      containsPair('skip_firebase_distribution', true),
    );
  });

  test('logs tail passes the log source through', () async {
    final h = await _start((_) => (200, {'lines': <String>[]}));
    await h.call('nexsoft_admin_logs_tail', {'source': 'novnc'});

    expect(h.sent.single.body['source'], 'novnc');
  });

  test('a server error comes back as an error result, not a crash', () async {
    final h = await _start(
      (_) => (
        403,
        {
          'error': {'code': 'forbidden', 'message': 'Admin only'},
        },
      ),
    );
    final result = await h.call('nexsoft_hot_reload');

    expect(result.isError, isTrue);
    expect(_text(result), contains('Admin only'));
  });
}
