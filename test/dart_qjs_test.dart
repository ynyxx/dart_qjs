import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_qjs/dart_qjs.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterQjs', () {
    test('provides fetch, Request, Response and Headers extensions', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      final result = qjs.evaluate(r'''
(() => ({
	fetchType: typeof fetch,
	headersType: typeof Headers,
	requestType: typeof Request,
	responseType: typeof Response,
	headerValue: new Headers([['X-Test', '1']]).get('x-test'),
	requestUrl: new Request('https://example.com/items', { method: 'post' }).method,
}))()
''');

      expect(result, {
        'fetchType': 'function',
        'headersType': 'function',
        'requestType': 'function',
        'responseType': 'function',
        'headerValue': '1',
        'requestUrl': 'POST',
      });
    });

    test('fetch performs http requests with dart:io', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var largeText = "1";
      for (int i = 0; i < 20; i++) {
        largeText = largeText + largeText;
      }

      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        expect(request.method, 'POST');
        expect(request.headers.value('x-token'), 'abc');
        expect(body, '{"hello":"world"}');
        request.response.statusCode = HttpStatus.created;
        request.response.reasonPhrase = 'Created';
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('x-reply', 'ok');
        request.response.write('{"received":"$largeText"}');
        await request.response.close();
      });

      final qjs = FlutterQjs();
      final dispatched = qjs.dispatch();
      addTearDown(() async {
        qjs.close();
        await dispatched;
      });

      final result =
          await (qjs.evaluate('''
fetch('http://${server.address.host}:${server.port}/api', {
	method: 'post',
	headers: {
		'content-type': 'application/json',
		'x-token': 'abc',
	},
	body: JSON.stringify({ hello: 'world' }),
}).then(async (response) => ({
	status: response.status,
	statusText: response.statusText,
	ok: response.ok,
	reply: response.headers.get('x-reply'),
	data: await response.json(),
}))
''')
              as Future);

      expect(result, {
        'status': 201,
        'statusText': 'Created',
        'ok': true,
        'reply': 'ok',
        'data': {'received': largeText},
      });
    });

    test('fetch supports binary response bodies', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.binary;
        request.response.add([1, 2, 3, 4]);
        await request.response.close();
      });

      final qjs = FlutterQjs();
      final dispatched = qjs.dispatch();
      addTearDown(() async {
        qjs.close();
        await dispatched;
      });

      final result =
          await (qjs.evaluate('''
fetch('http://${server.address.host}:${server.port}/bytes')
	.then((response) => response.arrayBuffer())
	.then((buffer) => Array.from(new Uint8Array(buffer)))
''')
              as Future);

      expect(result, [1, 2, 3, 4]);
    });

    test('provides URL and URLSearchParams extensions', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      final result = qjs.evaluate(r'''
(() => ({
	urlType: typeof URL,
	paramsType: typeof URLSearchParams,
	href: new URL('/child?x=1', 'https://example.com/base/index.html').href,
	origin: new URL('/child?x=1', 'https://example.com/base/index.html').origin,
	pathname: new URL('/child?x=1', 'https://example.com/base/index.html').pathname,
	searchValue: new URL('/child?x=1', 'https://example.com/base/index.html').searchParams.get('x'),
	params: new URLSearchParams({ a: '1', space: 'hello world' }).toString(),
}))()
''');

      expect(result, {
        'urlType': 'function',
        'paramsType': 'function',
        'href': 'https://example.com/child?x=1',
        'origin': 'https://example.com',
        'pathname': '/child',
        'searchValue': '1',
        'params': 'a=1&space=hello+world',
      });
    });

    test('provides TextEncoder and TextDecoder extensions', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      final result = qjs.evaluate(r'''
(() => {
	const encoded = Array.from(new TextEncoder().encode('A你🙂'));
	const decoded = new TextDecoder().decode(new Uint8Array(encoded));
	return {
		encoderType: typeof TextEncoder,
		decoderType: typeof TextDecoder,
		encoded,
		decoded,
	};
})()
''');

      expect(result, {
        'encoderType': 'function',
        'decoderType': 'function',
        'encoded': [65, 228, 189, 160, 240, 159, 153, 130],
        'decoded': 'A你🙂',
      });
    });

    test('supports setTimeout and setInterval', () async {
      final qjs = FlutterQjs();
      final dispatched = qjs.dispatch();
      addTearDown(() async {
        qjs.close();
        await dispatched;
      });

      final timeoutResult =
          qjs.evaluate(r'''
new Promise((resolve) => {
	setTimeout((prefix, value) => resolve(`${prefix}:${value}`), 5, 'done', 7);
})
''')
              as Future;

      final intervalResult =
          qjs.evaluate(r'''
new Promise((resolve) => {
	let tick = 0;
	const values = [];
	const timer = setInterval(() => {
		tick += 1;
		values.push(tick);
		if (tick === 3) {
			clearInterval(timer);
			resolve(values);
		}
	}, 1);
})
''')
              as Future;

      expect(await timeoutResult, 'done:7');
      expect(await intervalResult, [1, 2, 3]);
    });

    test('routes console output through the custom handler', () {
      final records = <Map<String, dynamic>>[];
      final qjs = FlutterQjs(
        consoleHandler: (level, values) {
          records.add({'level': level, 'values': values});
        },
      );
      addTearDown(qjs.close);

      qjs.evaluate(r'''
console.log('hello', 1);
console.error('boom', { ok: false });
console.assert(false, 'failed');
''');

      expect(records, [
        {
          'level': 'log',
          'values': ['hello', 1],
        },
        {
          'level': 'error',
          'values': [
            'boom',
            {'ok': false},
          ],
        },
        {
          'level': 'assert',
          'values': ['failed'],
        },
      ]);
    });

    test('keeps URL.search and searchParams in sync', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      final result = qjs.evaluate(r'''
(() => {
	const url = new URL('https://example.com/path?a=1&a=2');
	url.searchParams.set('a', '3');
	url.searchParams.append('b', 'hello world');
	url.hash = 'section';
	return {
		href: url.href,
		search: url.search,
		allA: url.searchParams.getAll('a'),
		b: url.searchParams.get('b'),
		hash: url.hash,
	};
})()
''');

      expect(result, {
        'href': 'https://example.com/path?a=3&b=hello+world#section',
        'search': '?a=3&b=hello+world',
        'allA': ['3'],
        'b': 'hello world',
        'hash': '#section',
      });
    });

    test('executes JavaScript and produces hello', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      final result = qjs.evaluate(r'''
(() => {
	const message = 'hello';
	return message;
})()
''');

      expect(result, 'hello');
    });

    test('converts common JavaScript values back to Dart', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      final result =
          qjs.evaluate(r'''
(() => ({
	boolValue: true,
	intValue: 7,
	doubleValue: 2.5,
	stringValue: 'dart',
	listValue: [1, 'two', false],
	bytesValue: new Uint8Array([1, 2, 3, 4]).buffer,
	mapValue: new Map([
		['alpha', 1],
		['beta', 2],
	]),
}))()
''')
              as Map;

      expect(result['boolValue'], isTrue);
      expect(result['intValue'], 7);
      expect(result['doubleValue'], 2.5);
      expect(result['stringValue'], 'dart');
      expect(result['listValue'], [1, 'two', false]);
      expect(result['bytesValue'], Uint8List.fromList([1, 2, 3, 4]));
      expect(result['mapValue'], {'alpha': 1, 'beta': 2});
    });

    test('invokes JavaScript functions from Dart', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      final fn = qjs.evaluate(r'(name) => `hello ${name}`') as JSInvokable;
      addTearDown(fn.free);

      expect(fn.invoke(['copilot']), 'hello copilot');
    });

    test('passes Dart callbacks into JavaScript', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      final fn =
          qjs.evaluate('(callback) => callback("copilot", 3)') as JSInvokable;
      addTearDown(fn.free);

      final result = fn.invoke([(String name, int count) => '$name:$count']);

      expect(result, 'copilot:3');
    });

    test(
      'close stops dispatch and recreates the event port on reuse',
      () async {
        final qjs = FlutterQjs();
        addTearDown(qjs.close);

        final dispatched = qjs.dispatch();
        expect(qjs.evaluate('1 + 1'), 2);

        qjs.close();
        await expectLater(dispatched, completes);

        expect(qjs.evaluate('2 + 3'), 5);
      },
    );

    test('close is safe after manually closing the event port', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      expect(qjs.evaluate('1 + 1'), 2);

      qjs.port.close();

      expect(qjs.close, returnsNormally);
    });

    test('surfaces JavaScript exceptions as JSError', () {
      final qjs = FlutterQjs();
      addTearDown(qjs.close);

      expect(
        () => qjs.evaluate('throw new Error("boom")'),
        throwsA(
          isA<JSError>().having(
            (error) => error.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });
  });

  group('IsolateQjs', () {
    test('evaluates scripts asynchronously', () async {
      final qjs = IsolateQjs();
      addTearDown(qjs.close);

      final result =
          await qjs.evaluate(r'''
(() => ({
	answer: 42,
	values: [1, 2, 3],
}))()
''')
              as Map;

      expect(result['answer'], 42);
      expect(result['values'], [1, 2, 3]);
    });

    test('loads modules through the async module handler', () async {
      final qjs = IsolateQjs(
        moduleHandler: (name) async {
          if (name == 'math') {
            return 'export const add = (a, b) => a + b;';
          }
          throw Exception('unknown module: $name');
        },
      );
      addTearDown(qjs.close);

      final result = await qjs.evaluate(r'''
import('math').then(({ add }) => add(2, 5))
''');

      expect(result, 7);
    });

    test('routes isolate console output through the custom handler', () async {
      final records = <Map<String, dynamic>>[];
      final qjs = IsolateQjs(
        consoleHandler: (level, values) {
          records.add({'level': level, 'values': values});
        },
      );
      addTearDown(qjs.close);

      await qjs.evaluate(r'''
console.warn('from isolate', 9);
''');

      expect(records, [
        {
          'level': 'warn',
          'values': ['from isolate', 9],
        },
      ]);
    });

    test(
      'propagates JavaScript exceptions across the isolate boundary',
      () async {
        final qjs = IsolateQjs();
        addTearDown(qjs.close);

        await expectLater(
          qjs.evaluate('throw new Error("isolate boom")'),
          throwsA(
            isA<JSError>().having(
              (error) => error.message,
              'message',
              contains('isolate boom'),
            ),
          ),
        );
      },
    );
  });
}
