import 'dart:async';
import 'dart:io';

import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:custom_lint/src/plugin_delegate.dart';
import 'package:custom_lint/src/runner.dart';
import 'package:custom_lint/src/v2/custom_lint_analyzer_plugin.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<List<AnalysisErrorsParams>> runServerInCliModeForApp(
  Directory directory,
  // to ignoreErrors as we cannot explictly handle errors
) async {
  final runner = await startRunnerForApp(directory);
  return runner.getLints(reload: false);
}

Future<CustomLintRunner> startRunnerForApp(
  Directory directory, {
  bool ignoreErrors = false,
}) async {
  final runner = CustomLintRunner(
    // TODO use IO override to mock & test stdout/stderr
    CustomLintServer.run(
      delegate: CommandCustomLintDelegate(),
      watchMode: false,
    ),
    directory,
  );
  addTearDown(runner.close);

  if (!ignoreErrors) {
    runner.channel
      ..responseErrors.listen((event) {
        fail('${event.message} ${event.code}\n${event.stackTrace}');
      })
      ..pluginErrors.listen((event) {
        fail('${event.message}\n${event.stackTrace}');
      });
  }

  await runner.initialize();
  return runner;
}

extension LogFile on Directory {
  File get log {
    return File(p.join(path, 'custom_lint.log'));
  }
}
