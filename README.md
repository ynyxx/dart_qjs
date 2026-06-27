# dart_qjs

`dart_qjs` is a QuickJS binding for Dart built with `dart:ffi`.

This project was rebuilt from the ideas and API shape of
[`ekibun/flutter_qjs`](https://github.com/ekibun/flutter_qjs), but its biggest
difference is the packaging model: it uses **Dart native assets** instead of a
Flutter plugin layout. Native code is built through a Dart build hook, bundled
as a native asset, and loaded automatically by the Dart toolchain.

Another important difference is the JavaScript engine source: the original
project used upstream QuickJS, while this project builds against
[`quickjs-ng`](https://github.com/quickjs-ng/quickjs).

## Why this package

- Run JavaScript with QuickJS from Dart.
- Keep an API close to the original `flutter_qjs` project.
- Use `quickjs-ng` instead of upstream QuickJS.
- Use Dart native assets instead of maintaining platform plugin glue.
- Build the native library with CMake through `native_toolchain_cmake`.

## Native assets

The native-assets-based workflow is the main reason this package exists.

At build time, the hook in `hook/build.dart`:

- clones `quickjs-ng`
- builds the native library with CMake
- registers the resulting dynamic library as a Dart native asset

For consumers, that means:

- no manual `DynamicLibrary.open(...)`
- no hand-written platform loader code
- no Flutter plugin scaffolding just to ship a native library

## Prerequisites

Before using the package, make sure the following tools are available in your
environment:

- Dart SDK `^3.11.4`
- `git`
- CMake
- a working native toolchain for your target platform

The build hook currently clones `quickjs-ng` during the build, so network access
is also required unless you adapt the hook to use a vendored source tree.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
	dart_qjs: ^1.0.0
```

Then fetch dependencies:

```bash
dart pub get
```

The native library is built as part of the native assets workflow when the
package is compiled or tested.

## Quick start

The main engine class is currently named `FlutterQjs` for API compatibility with
the upstream project.

```dart
import 'package:dart_qjs/dart_qjs.dart';

void main() {
	final engine = FlutterQjs();
	engine.dispatch();

	try {
		final result = engine.evaluate(r'''
(() => {
	const name = 'QuickJS';
	return `hello ${name}`;
})()
''');

		print(result);
	} finally {
		engine.close();
	}
}
```

## Main-thread engine

`FlutterQjs` executes JavaScript synchronously and exposes a small event loop for
pending QuickJS jobs.

```dart
final engine = FlutterQjs(
	stackSize: 1024 * 1024,
	timeout: 1000,
	memoryLimit: 16 * 1024 * 1024,
);

engine.dispatch();

final result = engine.evaluate('1 + 2');
print(result); // 3

engine.close();
```

Notes:

- `evaluate()` is synchronous on the main-thread engine.
- `dispatch()` processes pending QuickJS jobs from the receive port.
- `close()` closes the receive port automatically and stops `dispatch()`.

## JavaScript extensions

The package currently adds these browser-compatible globals:

- `URL`
- `URLSearchParams`
- `TextEncoder`
- `TextDecoder`
- `fetch`
- `Headers`
- `Request`
- `Response`
- `setTimeout`
- `setInterval`
- `clearTimeout`
- `clearInterval`
- `console`

`fetch` is implemented with Dart standard library networking (`dart:io`
`HttpClient`), so it works in Dart and Flutter desktop/server environments that
allow socket access.

`console` output can be redirected with `consoleHandler`:

```dart
final engine = FlutterQjs(
	consoleHandler: (level, values) {
		stderr.writeln('[$level] ${values.join(' ')}');
	},
);
```

## Isolate engine

If you want asynchronous evaluation or async module loading, use `IsolateQjs`.

```dart
final engine = IsolateQjs(
	moduleHandler: (String module) async {
		if (module == 'hello') {
			return 'export default (name) => `hello ${name}!`;';
		}
		throw Exception('Module not found: $module');
	},
);

final result = await engine.evaluate(r'''
import('hello').then(({ default: greet }) => greet('world'))
''');

print(result);
await engine.close();
```

Notes:

- `evaluate()` returns a `Future` on `IsolateQjs`.
- `moduleHandler` can be asynchronous.
- Functions used across isolate boundaries should be top-level or static.

## Modules

ES modules can be resolved from Dart with `moduleHandler`.

```dart
final engine = FlutterQjs(
	moduleHandler: (String module) {
		if (module == 'math') {
			return 'export const add = (a, b) => a + b;';
		}
		throw Exception('Module not found: $module');
	},
);

final add = engine.evaluate(r'''
import('math').then(({ add }) => add(2, 3))
''');
```

Module results are cached by QuickJS. To reset module state, close the engine
and create it again.

## Dart and JavaScript interop

The library converts common Dart values to JavaScript values and back.

| Dart | JavaScript |
| --- | --- |
| `bool` | `boolean` |
| `int` | `number` |
| `double` | `number` |
| `String` | `string` |
| `Uint8List` | `ArrayBuffer` |
| `List` | `Array` |
| `Map` | `Object` |
| `Future` | `Promise` |
| `JSError` | `Error` |
| other objects | wrapped as `DartObject` |

JavaScript functions returned into Dart implement `JSInvokable`.

```dart
final engine = FlutterQjs();
final fn = engine.evaluate('(name) => `hello ${name}`') as JSInvokable;

print(fn.invoke(['dart']));
fn.free();
engine.close();
```

JavaScript can also call Dart functions. Pass a Dart callback into JavaScript,
then store it on the JavaScript global object if you want JS code to call it
later.

```dart
final engine = FlutterQjs();

try {
	final setGlobal = engine.evaluate(
		'(key, value) => { globalThis[key] = value; }',
	) as JSInvokable;

	setGlobal.invoke([
		'formatMessage',
		(String name, int count) {
			// Replace this with your own Dart implementation.
			return '$name:$count';
		},
	]);
	setGlobal.free();

	final result = engine.evaluate(r'''
formatMessage('dart', 3).toUpperCase()
''');

	print(result); // DART:3
} finally {
	engine.close();
}
```

For `IsolateQjs`, wrap inline Dart callbacks with `IsolateFunction` before
passing them to JavaScript.

```dart
final engine = IsolateQjs();

try {
	final setGlobal = await engine.evaluate(
		'(key, value) => { globalThis[key] = value; }',
	) as JSInvokable;

	await setGlobal.invoke([
		'add',
		IsolateFunction((int a, int b) => a + b),
	]);
	setGlobal.free();

	print(await engine.evaluate('add(2, 3)')); // 5
} finally {
	await engine.close();
}
```

Important:

- Objects implementing `JSRef` should be released when you keep them around.
- Use `free()` or `JSRef.freeRecursive(...)` to release JS-backed references.
- Use `dup()` if you need to retain a reference past an invocation boundary.

## Error handling

JavaScript exceptions are surfaced as `JSError`.

```dart
try {
	engine.evaluate('throw new Error("boom")');
} on JSError catch (error) {
	print(error);
}
```

Unhandled promise rejections can also be observed with
`hostPromiseRejectionHandler`.

## Development

Useful commands while working on the package:

```bash
dart pub get
dart test
```

Because native assets are involved, the first build on a machine may take longer
than a pure Dart package.

## Credits

This project is derived from `flutter_qjs` by ekibun and contributors, with a
reworked package structure and native-assets-based build pipeline.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for the
full text.
