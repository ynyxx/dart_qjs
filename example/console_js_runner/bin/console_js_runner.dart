import 'dart:convert';
import 'dart:io';

import 'package:dart_qjs/dart_qjs.dart';

void main(List<String> arguments) {
  final engine = FlutterQjs();

  print('dart_qjs JavaScript Console');
  print('Enter JavaScript code. Finish with an empty line.');
  print('Type :quit on a new prompt to exit.');

  try {
    while (true) {
      stdout.write('\njs> ');
      final firstLine = stdin.readLineSync();
      if (firstLine == null || firstLine.trim() == ':quit') {
        break;
      }

      final lines = <String>[firstLine];
      while (true) {
        stdout.write('... ');
        final line = stdin.readLineSync();
        if (line == null || line.isEmpty) {
          break;
        }
        lines.add(line);
      }

      final source = lines.join('\n');
      if (source.trim().isEmpty) {
        continue;
      }

      try {
        final result = engine.evaluate(source);
        print(_formatResult(result));
      } on JSError catch (error) {
        stderr.writeln('JavaScript error: $error');
      } catch (error) {
        stderr.writeln('Error: $error');
      }
    }
  } finally {
    engine.close();
  }
}

String _formatResult(Object? value) {
  if (value == null) {
    return 'undefined';
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}
