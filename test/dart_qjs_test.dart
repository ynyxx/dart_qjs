import 'dart:typed_data';

import 'package:dart_qjs/dart_qjs.dart';
import 'package:test/test.dart';

void main() {
	group('FlutterQjs', () {
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

			final result = qjs.evaluate(r'''
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
''') as Map;

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

			final fn = qjs.evaluate('(callback) => callback("copilot", 3)')
				as JSInvokable;
			addTearDown(fn.free);

			final result = fn.invoke([
				(String name, int count) => '$name:$count',
			]);

			expect(result, 'copilot:3');
		});

		test('surfaces JavaScript exceptions as JSError', () {
			final qjs = FlutterQjs();
			addTearDown(qjs.close);

			expect(
				() => qjs.evaluate('throw new Error("boom")'),
				throwsA(
					isA<JSError>()
						.having((error) => error.message, 'message', contains('boom')),
				),
			);
		});
	});

	group('IsolateQjs', () {
		test('evaluates scripts asynchronously', () async {
			final qjs = IsolateQjs();
			addTearDown(qjs.close);

			final result = await qjs.evaluate(r'''
(() => ({
	answer: 42,
	values: [1, 2, 3],
}))()
''') as Map;

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

		test('propagates JavaScript exceptions across the isolate boundary', () async {
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
		});
	});
}