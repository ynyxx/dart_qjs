## 1.0.5

- Fix `TextDecoder` UTF-8 decoding for large payloads returned by `fetch`.
- Add coverage for large JSON response bodies in the `fetch` HTTP test.

## 1.0.4

- Add browser-compatible `URL`, `TextEncoder/TextDecoder`, `setTimeout`, `setInterval`, `fetch`.
- Add tests covering HTTP requests, response headers, and binary response
  bodies for the new `fetch` API.

## 1.0.3

- Let `FlutterQjs.close()` close the event port automatically.
- Allow `FlutterQjs` instances to recreate their event port after close.
- Document Dart callback usage from JavaScript.

## 1.0.2

- Fix FFI callback binding for runtime creation.

## 1.0.1

- Fix native asset library naming across non-web platforms.

## 1.0.0

- Initial version.
