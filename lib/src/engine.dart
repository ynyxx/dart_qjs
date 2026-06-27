part of '../dart_qjs.dart';

/// Handler function to manage js module.
typedef _JsModuleHandler = String Function(String name);

/// Handler to manage unhandled promise rejection.
typedef _JsHostPromiseRejectionHandler = void Function(dynamic reason);

/// Handler to receive console output from JavaScript.
typedef JsConsoleHandler = void Function(String level, List<dynamic> values);

/// Quickjs engine for flutter.
class FlutterQjs {
  Pointer<JSRuntime>? _rt;
  Pointer<JSContext>? _ctx;
  bool _closed = false;
  final HttpClient _httpClient = HttpClient();

  /// Max stack size for quickjs.
  final int? stackSize;

  /// Max stack size for quickjs.
  final int? timeout;

  /// Max memory for quickjs.
  final int? memoryLimit;

  /// Message Port for event loop.
  ///
  /// Calling [close] closes this port automatically and stops [dispatch].
  ReceivePort port = ReceivePort();

  /// Handler function to manage js module.
  final _JsModuleHandler? moduleHandler;

  /// Handler function to manage js module.
  final _JsHostPromiseRejectionHandler? hostPromiseRejectionHandler;

  /// Handler function to receive JavaScript console output.
  final JsConsoleHandler? consoleHandler;

  final Map<int, _QjsTimerEntry> _timers = HashMap();
  int _nextTimerId = 1;

  FlutterQjs({
    this.moduleHandler,
    this.stackSize,
    this.timeout,
    this.memoryLimit,
    this.hostPromiseRejectionHandler,
    this.consoleHandler,
  });

  _ensureEngine() {
    if (_rt != null) return;
    if (_closed) {
      port = ReceivePort();
      _closed = false;
    }
    final rt = jsNewRuntime(
      (ctx, type, ptr) {
        try {
          switch (type) {
            case JSChannelType.METHON:
              final pdata = ptr.cast<Pointer<JSValue>>();
              final argc = (pdata + 1).value.cast<Int32>().value;
              final pargs = [];
              for (var i = 0; i < argc; ++i) {
                pargs.add(
                  _jsToDart(
                    ctx,
                    Pointer.fromAddress(
                      (pdata + 2).value.address + sizeOfJSValue * i,
                    ),
                  ),
                );
              }
              final JSInvokable func = _jsToDart(ctx, (pdata + 3).value);
              return _dartToJs(
                ctx,
                func.invoke(pargs, _jsToDart(ctx, pdata.value)),
              );
            case JSChannelType.MODULE:
              if (moduleHandler == null) throw JSError('No ModuleHandler');
              final ret = moduleHandler!(
                ptr.cast<Utf8>().toDartString(),
              ).toNativeUtf8();
              Future.microtask(() {
                malloc.free(ret);
              });
              return ret.cast();
            case JSChannelType.PROMISE_TRACK:
              final err = _parseJSException(ctx, ptr);
              if (hostPromiseRejectionHandler != null) {
                hostPromiseRejectionHandler!(err);
              } else {
                print('unhandled promise rejection: $err');
              }
              return nullptr;
            case JSChannelType.FREE_OBJECT:
              final rt = ctx.cast<JSRuntime>();
              _DartObject.fromAddress(rt, ptr.address)?.free();
              return nullptr;
          }
          throw JSError('call channel with wrong type');
        } catch (e) {
          if (type == JSChannelType.FREE_OBJECT) {
            print('DartObject release error: $e');
            return nullptr;
          }
          if (type == JSChannelType.MODULE) {
            print('host Promise Rejection Handler error: $e');
            return nullptr;
          }
          final throwObj = _dartToJs(ctx, e);
          final err = jsThrow(ctx, throwObj);
          jsFreeValue(ctx, throwObj);
          if (type == JSChannelType.MODULE) {
            jsFreeValue(ctx, err);
            return nullptr;
          }
          return err;
        }
      },
      timeout ?? 0,
      port,
    );
    final stackSize = this.stackSize ?? 0;
    if (stackSize > 0) jsSetMaxStackSize(rt, stackSize);
    final memoryLimit = this.memoryLimit ?? 0;
    if (memoryLimit > 0) jsSetMemoryLimit(rt, memoryLimit);
    _rt = rt;
    _ctx = jsNewContext(rt);
    _installExtensions(_ctx!, this);
  }

  /// Free Runtime and Context which can be recreate when evaluate again.
  close() {
    port.close();
    _closed = true;
    final rt = _rt;
    final ctx = _ctx;
    _clearAllTimers();
    _executePendingJob();
    _httpClient.close(force: true);
    _rt = null;
    _ctx = null;
    if (ctx != null) jsFreeContext(ctx);
    if (rt == null) return;
    try {
      jsFreeRuntime(rt);
    } on String catch (e) {
      throw JSError(e);
    }
  }

  void _executePendingJob() {
    final rt = _rt;
    final ctx = _ctx;
    if (rt == null || ctx == null) return;
    while (true) {
      int err = jsExecutePendingJob(rt);
      if (err <= 0) {
        if (err < 0) print(_parseJSException(ctx));
        break;
      }
    }
  }

  /// Dispatch JavaScript Event loop.
  Future<void> dispatch() async {
    await for (final _ in port) {
      _executePendingJob();
    }
  }

  /// Evaluate js script.
  dynamic evaluate(String command, {String? name, int? evalFlags}) {
    _ensureEngine();
    final ctx = _ctx!;
    final jsval = jsEval(
      ctx,
      command,
      name ?? '<eval>',
      evalFlags ?? JSEvalFlag.GLOBAL,
    );
    if (jsIsException(jsval) != 0) {
      jsFreeValue(ctx, jsval);
      throw _parseJSException(ctx);
    }
    final result = _jsToDart(ctx, jsval);
    jsFreeValue(ctx, jsval);
    return result;
  }

  /// Set a property on `globalThis`.
  void setGlobal(String symbolName, dynamic value) {
    _ensureEngine();
    final ctx = _ctx!;
    final global = jsGetGlobalObject(ctx);
    try {
      _definePropertyValue(ctx, global, symbolName, value);
    } finally {
      jsFreeValue(ctx, global);
    }
  }

  int _setTimer(
    JSInvokable callback,
    int delayMs,
    List<dynamic> args,
    bool repeat,
  ) {
    final timerId = _nextTimerId++;
    JSRef.dupRecursive(callback);
    JSRef.dupRecursive(args);
    final duration = Duration(milliseconds: delayMs < 0 ? 0 : delayMs);

    void onFire() {
      final entry = _timers[timerId];
      if (entry == null) return;
      try {
        entry.callback.invoke(entry.args);
      } catch (error) {
        print('timer callback error: $error');
      } finally {
        if (!entry.repeat) _disposeTimer(timerId);
      }
    }

    final timer = repeat
        ? Timer.periodic(duration, (_) => onFire())
        : Timer(duration, onFire);
    _timers[timerId] = _QjsTimerEntry(
      callback: callback,
      args: args,
      timer: timer,
      repeat: repeat,
    );
    return timerId;
  }

  void _clearTimer(int timerId) {
    _disposeTimer(timerId);
  }

  void _emitConsole(String level, List<dynamic> values) {
    final handler = consoleHandler;
    if (handler != null) {
      handler(level, values);
      return;
    }
    final text = values.map((value) => value?.toString() ?? 'null').join(' ');
    if (level == 'log') {
      print(text);
      return;
    }
    print('[$level] $text');
  }

  Future<Map<String, dynamic>> _fetch(Map<dynamic, dynamic> request) async {
    final urlValue = request['url'];
    if (urlValue == null) {
      throw JSError('fetch requires a request url');
    }

    final uri = Uri.parse(urlValue.toString());
    final method = (request['method']?.toString() ?? 'GET').toUpperCase();
    final headers = <String, String>{};
    final headerEntries = request['headers'];
    if (headerEntries is Map) {
      for (final entry in headerEntries.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    }

    final httpRequest = await _httpClient.openUrl(method, uri);
    headers.forEach(httpRequest.headers.set);

    final body = request['body'];
    if (body is Uint8List) {
      httpRequest.add(body);
    } else if (body is List<int>) {
      httpRequest.add(Uint8List.fromList(body));
    } else if (body is String) {
      httpRequest.add(utf8.encode(body));
    } else if (body != null) {
      throw JSError('Unsupported fetch body type: ${body.runtimeType}');
    }

    final response = await httpRequest.close();
    final responseBytes = await response
        .fold<BytesBuilder>(BytesBuilder(copy: false), (builder, chunk) {
          builder.add(chunk);
          return builder;
        })
        .then((builder) => builder.takeBytes());
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name] = values.join(', ');
    });

    return {
      'status': response.statusCode,
      'statusText': response.reasonPhrase,
      'ok': response.statusCode >= 200 && response.statusCode < 300,
      'url': uri.toString(),
      'headers': responseHeaders,
      'body': responseBytes,
    };
  }

  void _disposeTimer(int timerId) {
    final entry = _timers.remove(timerId);
    if (entry == null) return;
    entry.timer.cancel();
    JSRef.freeRecursive(entry.callback);
    JSRef.freeRecursive(entry.args);
  }

  void _clearAllTimers() {
    final timerIds = _timers.keys.toList(growable: false);
    for (final timerId in timerIds) {
      _disposeTimer(timerId);
    }
  }
}

class _QjsTimerEntry {
  final JSInvokable callback;
  final List<dynamic> args;
  final Timer timer;
  final bool repeat;

  _QjsTimerEntry({
    required this.callback,
    required this.args,
    required this.timer,
    required this.repeat,
  });
}
