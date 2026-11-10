import 'package:is_tools_api/is_tools_api.dart';

import 'path_in_repo.dart';

/// What became of a run.
sealed class Outcome<O> {
  const Outcome();
}

/// It ran, and gave [output].
final class Ran<O> extends Outcome<O> {
  const Ran(this.output);

  final O output;
}

/// It did not run: the airlock denied it, the journey path was stopped, its
/// driver refused it, or this machine has no driver for its program. An
/// [Outcome] of every program, since [Never] is a subtype of every type.
final class Refused extends Outcome<Never> {
  const Refused(this.why);

  final String why;
}

/// [text] for the file at [path]. The driver decides whether it may be
/// written; that [path] stays inside the repo is settled by its type.
final class FileText {
  const FileText(this.path, this.text);

  final PathInRepo path;
  final String text;
}

/// What a started program is given.
final class Args {
  const Args(this.args, {this.stdin, this.inFolder = PathInRepo.root});

  final List<String> args;

  /// Written to the program's stdin, then closed. Null: stdin is closed at
  /// once.
  final String? stdin;

  /// The folder it runs in.
  final PathInRepo inFolder;
}

/// What a read found.
sealed class ReadResult {
  const ReadResult();
}

final class ReadText extends ReadResult {
  const ReadText(this.text);

  final String text;
}

/// No file at the path.
final class ReadMissing extends ReadResult {
  const ReadMissing();
}

/// Written; [replaced] when a file was there before.
final class Wrote {
  const Wrote({required this.replaced});

  final bool replaced;
}

/// What a program did once it started.
///
/// One that never started is [Refused], with its own reason, so there is no
/// refused flag here and [forModel] never has to guess why a command did not
/// run.
final class ExecResult {
  const ExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.silentFor,
  });

  /// [forModel], as a tool's definition renders an [ExecResult] answer.
  static const output = Output<ExecResult>(_forModel);

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  /// Set when the command was killed for printing nothing for this long;
  /// null otherwise.
  final Duration? silentFor;

  /// What the model is told.
  ///
  /// stderr is INCLUDED even on success, and the exit code is always stated.
  /// A command that printed a warning and succeeded, and one that printed the
  /// same text and failed, are different events; a transcript that shows only
  /// stdout makes them identical. Exit 0 is not a measurement.
  String get forModel {
    final b = StringBuffer(switch ((timedOut, silentFor)) {
      (_, final quiet?) =>
        'printed nothing for ${quiet.inSeconds}s and was killed; no exit code',
      (true, null) => 'timed out and was killed; no exit code',
      (false, null) => 'exit $exitCode',
    });
    final anyOut = stdout.trim().isNotEmpty;
    final anyErr = stderr.trim().isNotEmpty;
    if (anyOut) b.write('\n--- stdout ---\n${stdout.trimRight()}');
    if (anyErr) b.write('\n--- stderr ---\n${stderr.trimRight()}');
    if (!anyOut && !anyErr) b.write(' (no output)');
    return b.toString();
  }
}

String _forModel(ExecResult result) => result.forModel;
