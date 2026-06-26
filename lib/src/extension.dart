part of '../dart_qjs.dart';

void _installExtensions(Pointer<JSContext> ctx, FlutterQjs engine) {
  final host = jsEval(
    ctx,
    r'''
(() => {
  const value = {};
  Object.defineProperty(globalThis, '__dart_qjs__', {
    configurable: true,
    writable: true,
    value,
  });
  return value;
})()
''',
    '<dart_qjs:extension/create-host>',
    JSEvalFlag.GLOBAL,
  );
  if (jsIsException(host) != 0) {
    jsFreeValue(ctx, host);
    throw _parseJSException(ctx);
  }
  _definePropertyValue(ctx, host, 'setTimer', (
    dynamic callback,
    dynamic delay,
    dynamic args,
    dynamic repeat,
  ) {
    if (callback is! JSInvokable) {
      throw JSError('Timer callback must be a function');
    }
    final timerArgs = args is List ? args.cast<dynamic>() : <dynamic>[];
    return engine._setTimer(
      callback,
      delay is int ? delay : (delay is double ? delay.toInt() : 0),
      timerArgs,
      repeat == true,
    );
  });
  _definePropertyValue(ctx, host, 'clearTimer', (dynamic timerId) {
    if (timerId is int) {
      engine._clearTimer(timerId);
    } else if (timerId is double) {
      engine._clearTimer(timerId.toInt());
    }
    return null;
  });
  _definePropertyValue(ctx, host, 'consoleWrite', (
    dynamic level,
    dynamic values,
  ) {
    engine._emitConsole(
      level?.toString() ?? 'log',
      values is List ? values.cast<dynamic>() : <dynamic>[values],
    );
    return null;
  });
  _definePropertyValue(ctx, host, 'fetch', (dynamic request) {
    if (request is! Map) {
      throw JSError('fetch request must be an object');
    }
    return engine._fetch(request.cast<dynamic, dynamic>());
  });
  jsFreeValue(ctx, host);

  _installExtension(
    ctx,
    _timerAndConsoleExtensionSource,
    '<dart_qjs:extension/host>',
  );
  _installExtension(
    ctx,
    _textEncodingExtensionSource,
    '<dart_qjs:extension/text-encoding>',
  );
  _installExtension(ctx, _urlExtensionSource, '<dart_qjs:extension/url>');
  _installExtension(ctx, _fetchExtensionSource, '<dart_qjs:extension/fetch>');
}

void _installExtension(Pointer<JSContext> ctx, String source, String name) {
  final result = jsEval(ctx, source, name, JSEvalFlag.GLOBAL);
  if (jsIsException(result) != 0) {
    jsFreeValue(ctx, result);
    throw _parseJSException(ctx);
  }
  jsFreeValue(ctx, result);
}

const _urlExtensionSource = r'''
(() => {
  if (typeof globalThis.URL === 'function' &&
      typeof globalThis.URLSearchParams === 'function') {
    return;
  }

  const specialSchemes = new Set(['ftp:', 'file:', 'http:', 'https:', 'ws:', 'wss:']);

  function percentEncode(value) {
    return encodeURIComponent(String(value)).replace(/%20/g, '+');
  }

  function percentDecode(value) {
    return decodeURIComponent(String(value).replace(/\+/g, '%20'));
  }

  function parseParams(input) {
    const entries = [];
    if (input == null) return entries;
    let source = String(input);
    if (source.startsWith('?')) source = source.slice(1);
    if (source === '') return entries;
    for (const pair of source.split('&')) {
      if (pair === '') continue;
      const index = pair.indexOf('=');
      const rawName = index < 0 ? pair : pair.slice(0, index);
      const rawValue = index < 0 ? '' : pair.slice(index + 1);
      entries.push([percentDecode(rawName), percentDecode(rawValue)]);
    }
    return entries;
  }

  class URLSearchParams {
    constructor(init = '') {
      this._entries = [];
      if (typeof init === 'string') {
        this._entries = parseParams(init);
      } else if (init && typeof init[Symbol.iterator] === 'function') {
        for (const pair of init) {
          if (!pair || pair.length < 2) {
            throw new TypeError('Each query pair must be an iterable [name, value]');
          }
          this.append(pair[0], pair[1]);
        }
      } else if (init && typeof init === 'object') {
        for (const key of Object.keys(init)) this.append(key, init[key]);
      }
    }

    append(name, value) {
      this._entries.push([String(name), String(value)]);
      this._updateUrl();
    }

    delete(name) {
      name = String(name);
      this._entries = this._entries.filter((entry) => entry[0] !== name);
      this._updateUrl();
    }

    get(name) {
      name = String(name);
      const entry = this._entries.find((entry) => entry[0] === name);
      return entry ? entry[1] : null;
    }

    getAll(name) {
      name = String(name);
      return this._entries.filter((entry) => entry[0] === name).map((entry) => entry[1]);
    }

    has(name) {
      name = String(name);
      return this._entries.some((entry) => entry[0] === name);
    }

    set(name, value) {
      name = String(name);
      value = String(value);
      let found = false;
      const entries = [];
      for (const entry of this._entries) {
        if (entry[0] === name) {
          if (!found) {
            entries.push([name, value]);
            found = true;
          }
        } else {
          entries.push(entry);
        }
      }
      if (!found) entries.push([name, value]);
      this._entries = entries;
      this._updateUrl();
    }

    sort() {
      this._entries.sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
      this._updateUrl();
    }

    forEach(callback, thisArg = undefined) {
      for (const [name, value] of this._entries) callback.call(thisArg, value, name, this);
    }

    keys() {
      return this._entries.map((entry) => entry[0])[Symbol.iterator]();
    }

    values() {
      return this._entries.map((entry) => entry[1])[Symbol.iterator]();
    }

    entries() {
      return this._entries.map((entry) => [entry[0], entry[1]])[Symbol.iterator]();
    }

    [Symbol.iterator]() {
      return this.entries();
    }

    toString() {
      return this._entries
        .map(([name, value]) => `${percentEncode(name)}=${percentEncode(value)}`)
        .join('&');
    }

    _bindUrl(url) {
      Object.defineProperty(this, '_url', {
        value: url,
        writable: true,
        configurable: true,
      });
    }

    _updateUrl() {
      if (this._url) this._url._record.search = this.toString() ? `?${this}` : '';
    }
  }

  function normalizePath(path) {
    const absolute = path.startsWith('/');
    const trailing = path.endsWith('/');
    const parts = [];
    for (const part of path.split('/')) {
      if (part === '' || part === '.') continue;
      if (part === '..') {
        if (parts.length > 0) parts.pop();
        continue;
      }
      parts.push(part);
    }
    let result = `${absolute ? '/' : ''}${parts.join('/')}`;
    if (trailing && result !== '/') result += '/';
    return result || (absolute ? '/' : '');
  }

  function parseAbsolute(input) {
    const match = String(input).match(/^([A-Za-z][A-Za-z0-9+.-]*:)(.*)$/);
    if (!match) return null;
    const record = {
      protocol: match[1].toLowerCase(),
      username: '',
      password: '',
      hostname: '',
      port: '',
      pathname: '',
      search: '',
      hash: '',
    };
    let rest = match[2];
    const hashIndex = rest.indexOf('#');
    if (hashIndex >= 0) {
      record.hash = rest.slice(hashIndex);
      rest = rest.slice(0, hashIndex);
    }
    const searchIndex = rest.indexOf('?');
    if (searchIndex >= 0) {
      record.search = rest.slice(searchIndex);
      rest = rest.slice(0, searchIndex);
    }
    if (rest.startsWith('//')) {
      rest = rest.slice(2);
      const slashIndex = rest.search(/[\/\\]/);
      const authority = slashIndex < 0 ? rest : rest.slice(0, slashIndex);
      rest = slashIndex < 0 ? '' : rest.slice(slashIndex);
      const atIndex = authority.lastIndexOf('@');
      const hostPort = atIndex < 0 ? authority : authority.slice(atIndex + 1);
      if (atIndex >= 0) {
        const userInfo = authority.slice(0, atIndex);
        const colonIndex = userInfo.indexOf(':');
        record.username = colonIndex < 0 ? userInfo : userInfo.slice(0, colonIndex);
        record.password = colonIndex < 0 ? '' : userInfo.slice(colonIndex + 1);
      }
      const portMatch = hostPort.match(/^(.*):([0-9]*)$/);
      record.hostname = (portMatch ? portMatch[1] : hostPort).toLowerCase();
      record.port = portMatch ? portMatch[2] : '';
    }
    record.pathname = normalizePath(rest || (specialSchemes.has(record.protocol) ? '/' : ''));
    return record;
  }

  function cloneRecord(record) {
    return {
      protocol: record.protocol,
      username: record.username,
      password: record.password,
      hostname: record.hostname,
      port: record.port,
      pathname: record.pathname,
      search: record.search,
      hash: record.hash,
    };
  }

  function parseRelative(input, base) {
    const record = cloneRecord(base);
    let rest = String(input);
    const hashIndex = rest.indexOf('#');
    record.hash = hashIndex >= 0 ? rest.slice(hashIndex) : '';
    if (hashIndex >= 0) rest = rest.slice(0, hashIndex);
    const searchIndex = rest.indexOf('?');
    record.search = searchIndex >= 0 ? rest.slice(searchIndex) : '';
    if (searchIndex >= 0) rest = rest.slice(0, searchIndex);
    if (rest.startsWith('//')) return parseAbsolute(`${record.protocol}${rest}${record.search}${record.hash}`);
    if (rest === '') {
      if (searchIndex < 0) record.search = base.search;
      return record;
    }
    if (rest.startsWith('/')) {
      record.pathname = normalizePath(rest);
      return record;
    }
    const basePath = base.pathname || '/';
    const directory = basePath.slice(0, basePath.lastIndexOf('/') + 1);
    record.pathname = normalizePath(`${directory}${rest}`);
    return record;
  }

  class URL {
    constructor(input, base = undefined) {
      let record = parseAbsolute(input);
      if (!record) {
        if (base === undefined) throw new TypeError('Invalid URL');
        const baseRecord = base instanceof URL ? base._record : parseAbsolute(base);
        if (!baseRecord) throw new TypeError('Invalid base URL');
        record = parseRelative(input, baseRecord);
      }
      this._record = record;
      this.searchParams = new URLSearchParams(record.search);
      this.searchParams._bindUrl(this);
    }

    get href() {
      const r = this._record;
      const user = r.username ? `${r.username}${r.password ? `:${r.password}` : ''}@` : '';
      const auth = r.hostname ? `//${user}${r.hostname}${r.port ? `:${r.port}` : ''}` : '';
      return `${r.protocol}${auth}${r.pathname}${r.search}${r.hash}`;
    }

    set href(value) {
      const record = parseAbsolute(value);
      if (!record) throw new TypeError('Invalid URL');
      this._record = record;
      this.searchParams = new URLSearchParams(record.search);
      this.searchParams._bindUrl(this);
    }

    get origin() {
      const r = this._record;
      if (!specialSchemes.has(r.protocol) || r.protocol === 'file:') return 'null';
      return `${r.protocol}//${r.hostname}${r.port ? `:${r.port}` : ''}`;
    }

    get protocol() { return this._record.protocol; }
    set protocol(value) {
      const protocol = String(value).replace(/:$/, '').toLowerCase();
      if (/^[A-Za-z][A-Za-z0-9+.-]*$/.test(protocol)) this._record.protocol = `${protocol}:`;
    }

    get username() { return this._record.username; }
    set username(value) { this._record.username = String(value); }

    get password() { return this._record.password; }
    set password(value) { this._record.password = String(value); }

    get host() {
      const r = this._record;
      return `${r.hostname}${r.port ? `:${r.port}` : ''}`;
    }
    set host(value) {
      const match = String(value).match(/^(.*):([0-9]*)$/);
      this._record.hostname = (match ? match[1] : String(value)).toLowerCase();
      this._record.port = match ? match[2] : '';
    }

    get hostname() { return this._record.hostname; }
    set hostname(value) { this._record.hostname = String(value).toLowerCase(); }

    get port() { return this._record.port; }
    set port(value) { this._record.port = String(value).replace(/[^0-9]/g, ''); }

    get pathname() { return this._record.pathname; }
    set pathname(value) {
      const path = String(value);
      this._record.pathname = normalizePath(path.startsWith('/') ? path : `/${path}`);
    }

    get search() { return this._record.search; }
    set search(value) {
      const search = String(value);
      this._record.search = search === '' ? '' : search.startsWith('?') ? search : `?${search}`;
      this.searchParams = new URLSearchParams(this._record.search);
      this.searchParams._bindUrl(this);
    }

    get hash() { return this._record.hash; }
    set hash(value) {
      const hash = String(value);
      this._record.hash = hash === '' ? '' : hash.startsWith('#') ? hash : `#${hash}`;
    }

    toString() { return this.href; }
    toJSON() { return this.href; }
  }

  Object.defineProperty(URLSearchParams.prototype, Symbol.toStringTag, {
    value: 'URLSearchParams',
    configurable: true,
  });
  Object.defineProperty(URL.prototype, Symbol.toStringTag, {
    value: 'URL',
    configurable: true,
  });

  if (typeof globalThis.URLSearchParams !== 'function') {
    Object.defineProperty(globalThis, 'URLSearchParams', {
      value: URLSearchParams,
      writable: true,
      configurable: true,
    });
  }
  if (typeof globalThis.URL !== 'function') {
    Object.defineProperty(globalThis, 'URL', {
      value: URL,
      writable: true,
      configurable: true,
    });
  }
})();
''';

const _timerAndConsoleExtensionSource = r'''
(() => {
  const host = globalThis.__dart_qjs__;
  if (!host) return;

  const installTimer = (name, repeat) => {
    Object.defineProperty(globalThis, name, {
      configurable: true,
      writable: true,
      value(callback, delay = 0, ...args) {
        if (typeof callback !== 'function') {
          throw new TypeError(`${name} callback must be a function`);
        }
        return host.setTimer(callback, Number(delay) || 0, args, repeat);
      },
    });
  };

  installTimer('setTimeout', false);
  installTimer('setInterval', true);

  Object.defineProperty(globalThis, 'clearTimeout', {
    configurable: true,
    writable: true,
    value(timerId) {
      host.clearTimer(timerId);
    },
  });

  Object.defineProperty(globalThis, 'clearInterval', {
    configurable: true,
    writable: true,
    value(timerId) {
      host.clearTimer(timerId);
    },
  });

  const consoleMethods = ['log', 'info', 'warn', 'error', 'debug'];
  const consoleObject = typeof globalThis.console === 'object' && globalThis.console !== null
    ? globalThis.console
    : {};

  for (const method of consoleMethods) {
    Object.defineProperty(consoleObject, method, {
      configurable: true,
      writable: true,
      value(...args) {
        host.consoleWrite(method, args);
      },
    });
  }

  Object.defineProperty(consoleObject, 'assert', {
    configurable: true,
    writable: true,
    value(condition, ...args) {
      if (condition) return;
      host.consoleWrite('assert', args.length === 0 ? ['Assertion failed'] : args);
    },
  });

  Object.defineProperty(globalThis, 'console', {
    configurable: true,
    writable: true,
    value: consoleObject,
  });
})();
''';

const _textEncodingExtensionSource = r'''
(() => {
  if (typeof globalThis.TextEncoder === 'function' &&
      typeof globalThis.TextDecoder === 'function') {
    return;
  }

  function toUint8Array(input) {
    if (input == null) return new Uint8Array(0);
    if (input instanceof Uint8Array) return input;
    if (ArrayBuffer.isView(input)) {
      return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    }
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    throw new TypeError('Expected ArrayBuffer or ArrayBufferView');
  }

  function encodeUtf8(value) {
    const bytes = [];
    for (const symbol of String(value)) {
      const codePoint = symbol.codePointAt(0);
      if (codePoint <= 0x7F) {
        bytes.push(codePoint);
      } else if (codePoint <= 0x7FF) {
        bytes.push(
          0xC0 | (codePoint >> 6),
          0x80 | (codePoint & 0x3F),
        );
      } else if (codePoint <= 0xFFFF) {
        bytes.push(
          0xE0 | (codePoint >> 12),
          0x80 | ((codePoint >> 6) & 0x3F),
          0x80 | (codePoint & 0x3F),
        );
      } else {
        bytes.push(
          0xF0 | (codePoint >> 18),
          0x80 | ((codePoint >> 12) & 0x3F),
          0x80 | ((codePoint >> 6) & 0x3F),
          0x80 | (codePoint & 0x3F),
        );
      }
    }
    return new Uint8Array(bytes);
  }

  function decodeUtf8(input, fatal = false) {
    const bytes = toUint8Array(input);
    const codeUnits = [];
    let index = 0;

    const fail = () => {
      if (fatal) throw new TypeError('The encoded data was not valid UTF-8');
      codeUnits.push(0xFFFD);
    };

    while (index < bytes.length) {
      const byte1 = bytes[index++];
      if (byte1 <= 0x7F) {
        codeUnits.push(byte1);
        continue;
      }

      let needed = 0;
      let codePoint = 0;
      let min = 0;

      if ((byte1 & 0xE0) === 0xC0) {
        needed = 1;
        codePoint = byte1 & 0x1F;
        min = 0x80;
      } else if ((byte1 & 0xF0) === 0xE0) {
        needed = 2;
        codePoint = byte1 & 0x0F;
        min = 0x800;
      } else if ((byte1 & 0xF8) === 0xF0) {
        needed = 3;
        codePoint = byte1 & 0x07;
        min = 0x10000;
      } else {
        fail();
        continue;
      }

      if (index + needed > bytes.length) {
        fail();
        break;
      }

      let valid = true;
      for (let offset = 0; offset < needed; offset++) {
        const next = bytes[index++];
        if ((next & 0xC0) !== 0x80) {
          valid = false;
          index -= 1;
          break;
        }
        codePoint = (codePoint << 6) | (next & 0x3F);
      }

      if (!valid ||
          codePoint < min ||
          codePoint > 0x10FFFF ||
          (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
        fail();
        continue;
      }

      if (codePoint <= 0xFFFF) {
        codeUnits.push(codePoint);
      } else {
        codePoint -= 0x10000;
        codeUnits.push(
          0xD800 + (codePoint >> 10),
          0xDC00 + (codePoint & 0x3FF),
        );
      }
    }

    return String.fromCharCode(...codeUnits);
  }

  class TextEncoder {
    get encoding() {
      return 'utf-8';
    }

    encode(input = '') {
      return encodeUtf8(input);
    }

    encodeInto(input = '', destination) {
      const bytes = encodeUtf8(input);
      const target = toUint8Array(destination);
      const written = Math.min(bytes.length, target.length);
      for (let i = 0; i < written; i++) target[i] = bytes[i];

      let read = 0;
      let produced = 0;
      for (const symbol of String(input)) {
        const size = encodeUtf8(symbol).length;
        if (produced + size > written) break;
        produced += size;
        read += symbol.length;
      }

      return { read, written };
    }
  }

  class TextDecoder {
    constructor(label = 'utf-8', options = {}) {
      const normalized = String(label).toLowerCase();
      if (normalized !== 'utf-8' && normalized !== 'utf8') {
        throw new RangeError('Only utf-8 is supported');
      }
      this.encoding = 'utf-8';
      this.fatal = options && options.fatal === true;
      this.ignoreBOM = options && options.ignoreBOM === true;
    }

    decode(input = new Uint8Array(0)) {
      let bytes = toUint8Array(input);
      if (!this.ignoreBOM &&
          bytes.length >= 3 &&
          bytes[0] === 0xEF &&
          bytes[1] === 0xBB &&
          bytes[2] === 0xBF) {
        bytes = bytes.slice(3);
      }
      return decodeUtf8(bytes, this.fatal);
    }
  }

  if (typeof globalThis.TextEncoder !== 'function') {
    Object.defineProperty(globalThis, 'TextEncoder', {
      configurable: true,
      writable: true,
      value: TextEncoder,
    });
  }

  if (typeof globalThis.TextDecoder !== 'function') {
    Object.defineProperty(globalThis, 'TextDecoder', {
      configurable: true,
      writable: true,
      value: TextDecoder,
    });
  }
})();
''';

const _fetchExtensionSource = r'''
(() => {
  if (typeof globalThis.fetch === 'function' &&
      typeof globalThis.Headers === 'function' &&
      typeof globalThis.Request === 'function' &&
      typeof globalThis.Response === 'function') {
    return;
  }

  const host = globalThis.__dart_qjs__;
  if (!host || typeof host.fetch !== 'function') return;

  function normalizeHeaderName(name) {
    return String(name).toLowerCase();
  }

  function normalizeHeaderValue(value) {
    return String(value).trim();
  }

  class Headers {
    constructor(init = undefined) {
      this._entries = [];
      if (init instanceof Headers) {
        for (const [name, value] of init.entries()) this.append(name, value);
      } else if (Array.isArray(init) || (init && typeof init[Symbol.iterator] === 'function')) {
        for (const pair of init) {
          if (!pair || pair.length < 2) throw new TypeError('Each header pair must be [name, value]');
          this.append(pair[0], pair[1]);
        }
      } else if (init && typeof init === 'object') {
        for (const key of Object.keys(init)) this.append(key, init[key]);
      }
    }

    append(name, value) {
      this._entries.push([normalizeHeaderName(name), normalizeHeaderValue(value)]);
    }

    delete(name) {
      name = normalizeHeaderName(name);
      this._entries = this._entries.filter((entry) => entry[0] !== name);
    }

    get(name) {
      name = normalizeHeaderName(name);
      const values = this._entries.filter((entry) => entry[0] === name).map((entry) => entry[1]);
      return values.length === 0 ? null : values.join(', ');
    }

    has(name) {
      name = normalizeHeaderName(name);
      return this._entries.some((entry) => entry[0] === name);
    }

    set(name, value) {
      name = normalizeHeaderName(name);
      value = normalizeHeaderValue(value);
      this._entries = this._entries.filter((entry) => entry[0] !== name);
      this._entries.push([name, value]);
    }

    forEach(callback, thisArg = undefined) {
      for (const [name, value] of this._entries) callback.call(thisArg, value, name, this);
    }

    keys() {
      return this._entries.map((entry) => entry[0])[Symbol.iterator]();
    }

    values() {
      return this._entries.map((entry) => entry[1])[Symbol.iterator]();
    }

    entries() {
      return this._entries.map((entry) => [entry[0], entry[1]])[Symbol.iterator]();
    }

    [Symbol.iterator]() {
      return this.entries();
    }

    toJSON() {
      const result = {};
      for (const [name, value] of this._entries) {
        result[name] = result[name] ? `${result[name]}, ${value}` : value;
      }
      return result;
    }
  }

  function cloneBody(body) {
    if (body == null) return null;
    if (typeof body === 'string') return body;
    if (body instanceof Uint8Array) return new Uint8Array(body);
    if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength));
    if (body instanceof ArrayBuffer) return new Uint8Array(body.slice(0));
    throw new TypeError('Unsupported body type');
  }

  function bodyToUint8Array(body) {
    if (body == null) return new Uint8Array(0);
    if (typeof body === 'string') return new TextEncoder().encode(body);
    return cloneBody(body);
  }

  function consumeBody(instance) {
    if (instance.bodyUsed) throw new TypeError('Body has already been consumed');
    instance.bodyUsed = true;
    return instance._body;
  }

  class Request {
    constructor(input, init = undefined) {
      if (input instanceof Request) {
        this.url = input.url;
        this.method = input.method;
        this.headers = new Headers(input.headers);
        this._body = cloneBody(input._body);
      } else {
        const url = input instanceof URL ? input.href : String(input);
        this.url = new URL(url).href;
        this.method = 'GET';
        this.headers = new Headers();
        this._body = null;
      }

      if (init && typeof init === 'object') {
        if (init.method != null) this.method = String(init.method).toUpperCase();
        if (init.headers != null) this.headers = new Headers(init.headers);
        if (Object.prototype.hasOwnProperty.call(init, 'body')) this._body = cloneBody(init.body);
      }

      this.bodyUsed = false;
    }

    clone() {
      if (this.bodyUsed) throw new TypeError('Body has already been consumed');
      return new Request(this);
    }

    async arrayBuffer() {
      const body = consumeBody(this);
      const bytes = bodyToUint8Array(body);
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    }

    async text() {
      const body = consumeBody(this);
      if (typeof body === 'string') return body;
      return new TextDecoder().decode(bodyToUint8Array(body));
    }

    async json() {
      return JSON.parse(await this.text());
    }
  }

  class Response {
    constructor(body = null, init = undefined) {
      this._body = cloneBody(body);
      this.bodyUsed = false;
      this.status = init && init.status != null ? Number(init.status) : 200;
      this.statusText = init && init.statusText != null ? String(init.statusText) : '';
      this.headers = new Headers(init && init.headers != null ? init.headers : undefined);
      this.url = init && init.url != null ? String(init.url) : '';
    }

    get ok() {
      return this.status >= 200 && this.status < 300;
    }

    clone() {
      if (this.bodyUsed) throw new TypeError('Body has already been consumed');
      return new Response(this._body, {
        status: this.status,
        statusText: this.statusText,
        headers: this.headers,
        url: this.url,
      });
    }

    async arrayBuffer() {
      const body = consumeBody(this);
      const bytes = bodyToUint8Array(body);
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    }

    async text() {
      const body = consumeBody(this);
      if (typeof body === 'string') return body;
      return new TextDecoder().decode(bodyToUint8Array(body));
    }

    async json() {
      return JSON.parse(await this.text());
    }
  }

  async function fetch(input, init = undefined) {
    const request = input instanceof Request ? new Request(input, init) : new Request(input, init);
    const requestBody = request._body == null
      ? null
      : typeof request._body === 'string'
      ? request._body
      : bodyToUint8Array(request._body);

    const result = await host.fetch({
      url: request.url,
      method: request.method,
      headers: request.headers.toJSON(),
      body: requestBody,
    });

    return new Response(result.body ?? null, {
      status: result.status,
      statusText: result.statusText,
      headers: result.headers,
      url: result.url,
    });
  }

  Object.defineProperty(Headers.prototype, Symbol.toStringTag, {
    value: 'Headers',
    configurable: true,
  });
  Object.defineProperty(Request.prototype, Symbol.toStringTag, {
    value: 'Request',
    configurable: true,
  });
  Object.defineProperty(Response.prototype, Symbol.toStringTag, {
    value: 'Response',
    configurable: true,
  });

  Object.defineProperty(globalThis, 'Headers', {
    configurable: true,
    writable: true,
    value: Headers,
  });
  Object.defineProperty(globalThis, 'Request', {
    configurable: true,
    writable: true,
    value: Request,
  });
  Object.defineProperty(globalThis, 'Response', {
    configurable: true,
    writable: true,
    value: Response,
  });
  Object.defineProperty(globalThis, 'fetch', {
    configurable: true,
    writable: true,
    value: fetch,
  });
})();
''';
