import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:logging/logging.dart';

const quickjsVersion = 'v0.15.0';

const quickjsUrl = 'https://github.com/quickjs-ng/quickjs';

Uri _findBuiltLibrary(Uri outputDirectory, String fileName) {
  final root = Directory.fromUri(outputDirectory);
  final matches = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.uri.pathSegments.isNotEmpty)
      .where((file) => file.uri.pathSegments.last == fileName)
      .toList();
  if (matches.isEmpty) {
    throw Exception('Failed to locate built library $fileName under ${root.path}');
  }
  matches.sort((left, right) => left.path.length.compareTo(right.path.length));
  return matches.first.uri;
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    final sourceDir = Directory(await getPackagePath('dart_qjs')).uri.resolve('src');
    final sourceDirPath = sourceDir.toFilePath();
    final quickjsDirPath = '$sourceDirPath${Platform.pathSeparator}quickjs';
    hierarchicalLoggingEnabled = true;

    final logger = Logger('dart_qjs')
      ..level = Level.ALL
      ..onRecord.listen((record) {
        print('${record.level.name}: ${record.time}: ${record.message}');
      });

    try {
      logger.info('Cloning quickjs from $quickjsUrl at version $quickjsVersion');
      Directory.current = sourceDirPath;
      if (Directory(quickjsDirPath).existsSync()) {
        Directory(quickjsDirPath).deleteSync(recursive: true);
      }
      final gitResult = Process.runSync("git", ["clone", "--depth", "1", "--branch", quickjsVersion, quickjsUrl, quickjsDirPath]);
      if (gitResult.exitCode != 0) {
        throw Exception('Failed to clone quickjs: ${gitResult.stderr}');
      }

      final builder = CMakeBuilder.create(
        name: 'flutter_qjs_plugin',
        sourceDir: sourceDir,
        defines: {
          'CMAKE_BUILD_TYPE': 'Release',
          'QJS_SOURCE_DIR_CMAKE': sourceDir.toFilePath(),
          'CMAKE_INSTALL_PREFIX': '${input.outputDirectory.toFilePath()}/install',
        },
        logger: logger,
      );

      await builder.run(input: input, output: output);
      if (input.config.buildCodeAssets) {
        final dylibName = input.config.code.targetOS.dylibFileName('flutter_qjs_plugin');
        final libraryUri = _findBuiltLibrary(input.outputDirectory, dylibName);
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: 'flutter_qjs_plugin',
            linkMode: DynamicLoadingBundled(),
            file: libraryUri,
          ),
        );
      }
      final buildJson = input.config.json;
      logger.info('Build output: $buildJson');
    }
    finally {
      logger.info('Cleaning up cloned quickjs directory');
      if (Directory(quickjsDirPath).existsSync()) {
        Directory(quickjsDirPath).deleteSync(recursive: true);
      }
    }
  });
}