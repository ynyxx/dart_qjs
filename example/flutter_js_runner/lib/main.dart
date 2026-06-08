import 'dart:convert';

import 'package:dart_qjs/dart_qjs.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dart_qjs Runner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: const Color(0xfff6f7f9),
        useMaterial3: true,
      ),
      home: const JavaScriptRunnerPage(),
    );
  }
}

class JavaScriptRunnerPage extends StatefulWidget {
  const JavaScriptRunnerPage({super.key});

  @override
  State<JavaScriptRunnerPage> createState() => _JavaScriptRunnerPageState();
}

class _JavaScriptRunnerPageState extends State<JavaScriptRunnerPage> {
  late final FlutterQjs _engine;
  final _controller = TextEditingController(
    text: '''(() => {
  const values = [1, 2, 3, 4];
  return {
    sum: values.reduce((total, value) => total + value, 0),
    message: 'Hello from QuickJS',
  };
})()''',
  );
  String _output = 'Press Run to execute the JavaScript code.';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _engine = FlutterQjs();
  }

  @override
  void dispose() {
    _controller.dispose();
    _engine.close();
    super.dispose();
  }

  void _runScript() {
    final source = _controller.text.trim();
    if (source.isEmpty) {
      setState(() {
        _hasError = true;
        _output = 'Enter JavaScript code before running it.';
      });
      return;
    }

    try {
      final result = _engine.evaluate(source);
      setState(() {
        _hasError = false;
        _output = _formatResult(result);
      });
    } on JSError catch (error) {
      setState(() {
        _hasError = true;
        _output = error.toString();
      });
    } catch (error) {
      setState(() {
        _hasError = true;
        _output = error.toString();
      });
    }
  }

  void _resetScript() {
    setState(() {
      _controller.text = '1 + 2';
      _hasError = false;
      _output = 'Press Run to execute the JavaScript code.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('dart_qjs JavaScript Runner'),
        actions: [
          IconButton(
            onPressed: _resetScript,
            tooltip: 'Reset code',
            icon: const Icon(Icons.restore),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 840;
              final editor = _EditorPanel(controller: _controller);
              final output = _OutputPanel(output: _output, hasError: _hasError);

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: editor),
                    const SizedBox(width: 16),
                    Expanded(child: output),
                  ],
                );
              }

              return Column(
                children: [
                  Expanded(child: editor),
                  const SizedBox(height: 16),
                  Expanded(child: output),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _runScript,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Run'),
      ),
    );
  }
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'JavaScript',
      child: TextField(
        controller: controller,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Enter JavaScript code',
        ),
      ),
    );
  }
}

class _OutputPanel extends StatelessWidget {
  const _OutputPanel({required this.output, required this.hasError});

  final String output;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final color = hasError ? Colors.red.shade900 : Colors.green.shade900;
    final background = hasError ? Colors.red.shade50 : Colors.green.shade50;

    return _Panel(
      title: hasError ? 'Error' : 'Result',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            output,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(child: child),
          ],
        ),
      ),
    );
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
