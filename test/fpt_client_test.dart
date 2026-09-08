import 'dart:convert';

import 'package:fpt_server_mcp/src/fpt_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('FptClient', () {
    test('caches /actions GET responses but not other paths', () async {
      var getCount = 0;
      final client = FptClient(
        baseUrl: 'https://example.test',
        apiKey: '',
        client: MockClient((request) async {
          if (request.url.path == '/actions') {
            getCount++;
            return http.Response(jsonEncode({'actions': []}), 200);
          }
          getCount++;
          return http.Response(jsonEncode({'jobs': []}), 200);
        }),
      );

      await client.getJson('/actions');
      await client.getJson('/actions'); // should hit cache
      await client.getJson('/jobs');
      await client.getJson('/jobs'); // uncached path, calls again

      expect(getCount, 3);
    });

    test('post clears the cache so a subsequent GET refetches', () async {
      var actionsBody = 'a';
      var getCount = 0;
      final client = FptClient(
        baseUrl: 'https://example.test',
        apiKey: '',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            actionsBody = 'b';
            return http.Response(jsonEncode({'ok': true}), 200);
          }
          getCount++;
          return http.Response(jsonEncode({'actions': actionsBody}), 200);
        }),
      );

      await client.getJson('/actions');
      await client.postJson('/jobs/x/cancel');
      final second = await client.getJson('/actions');

      expect(getCount, 2);
      expect(second['actions'], 'b');
    });

    test(
        'wraps an error response into FptRequestError with the API code/message',
        () async {
      final client = FptClient(
        baseUrl: 'https://example.test',
        apiKey: '',
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'error': {
                  'code': 'job.already_finished',
                  'message': 'Build đã kết thúc',
                },
              }),
            ),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      await expectLater(
        client.getJson('/jobs/x'),
        throwsA(
          isA<FptRequestError>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.code, 'code', 'job.already_finished')
              .having((e) => e.message, 'message', 'Build đã kết thúc'),
        ),
      );
    });

    test('sends the API key as X-API-Key when configured', () async {
      String? seenHeader;
      final client = FptClient(
        baseUrl: 'https://example.test',
        apiKey: 'secret-key',
        client: MockClient((request) async {
          seenHeader = request.headers['X-API-Key'];
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      await client.getJson('/health');
      expect(seenHeader, 'secret-key');
    });
  });
}
