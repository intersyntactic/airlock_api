import 'package:is_tools_api/is_tools_api.dart';

/// What a tool's code returns for a call: a run whose outcome it needs
/// before it can answer, its answer, or that it could not answer. [A] is the
/// type of the answer, the tool's output type.
///
/// A tool holds no driver and touches nothing. The airlock follows its
/// result: it decides each run, has it carried out, records it, and gives
/// what became of it to the run's continuation. So a tool can describe
/// nothing a run cannot express.
///
/// Not an [Outcome], which is what happened to one run. A [Run] never reaches
/// the model: [Done]'s value does, rendered by the tool's definition, and
/// [Failed]'s reason does, as an error.
sealed class Result<A> {
  const Result();
}

/// Run [program] on [input], then continue with what became of the run.
///
/// The one effect a tool can describe. A read, a write and `git diff` are all
/// runs, of different programs, so a new program is a new [Program] and this
/// class does not change.
///
/// The continuation travels with the run, not in the tool, so one tool can
/// serve concurrent calls without keeping state for any of them. It is
/// private: what it is given comes from [next], after the airlock's decision,
/// never from whoever holds the run.
///
/// Typed only by the answer it leads to, [A]. The program's input and output
/// types stay inside, where [next] uses them, so whoever holds a run never
/// handles either, and a switch over a [Result] covers every run with
/// `case Run()`. Dart's generics are covariant: a caller passing an outcome
/// to the continuation itself would be checked only when it ran.
abstract final class Run<A> extends Result<A> {
  const Run._();

  /// For the airlock's decision and record.
  Program<Object?, Object?> get program;
  Object? get input;

  /// This run decided by [airlock], carried out on [home] if it allowed it,
  /// recorded by [airlock], and the result it leads to.
  ///
  /// The only way to carry out a run: no decision, no driver, and every
  /// outcome is recorded before the continuation sees it, a refusal
  /// included.
  Future<Result<A>> next(Home home, Airlock airlock);
}

/// A [Run] of a [Program] taking [I] and giving [O].
///
/// Made only by its program ([Program.run], [Program.runOrRefusal]), so [I]
/// is the program's own input type. Built from a program and an input side
/// by side, inference would widen [I] to fit both, and a [WriteFile] given a
/// `String` would compile.
final class _Run<I, O, A> extends Run<A> {
  const _Run(this.program, this.input, this._then) : super._();

  @override
  final Program<I, O> program;
  @override
  final I input;
  final Result<A> Function(Outcome<O> outcome) _then;

  @override
  Future<Result<A>> next(Home home, Airlock airlock) async {
    final Outcome<O> outcome = switch (await airlock.decide(this)) {
      Deny(:final why) => Refused(why),
      Allow() =>
        await program.on(Cleared._(home), input) ??
            Refused('this home cannot run ${program.name}'),
    };
    await airlock.record(this, outcome);
    return _then(outcome);
  }
}

/// The tool's answer. [value] reaches the model as its definition's
/// `Output` renders it.
final class Done<A> extends Result<A> {
  const Done(this.value);

  final A value;
}

/// The tool could not answer, because [why]. A [Result] of every tool, since
/// [Never] is a subtype of every type; the model is told [why] as an error.
final class Failed extends Result<Never> {
  const Failed(this.why);

  final String why;
}

/// Decides each run before it is carried out, and records each one after.
///
/// What intersyntactic's airlock implements. [Run.next] asks it, so a run is
/// carried out only once it has decided, and recorded whatever became of it.
abstract interface class Airlock {
  /// Whether [run] may be carried out: by asking the person, by a rule, or
  /// both.
  Future<Decision> decide(Run<Object?> run);

  /// What became of [run]: its output, or why it was refused.
  Future<void> record(Run<Object?> run, Outcome<Object?> outcome);
}

/// What the [Airlock] decided about one run.
sealed class Decision {
  const Decision();
}

/// The run may be carried out.
final class Allow extends Decision {
  const Allow();
}

/// The run is not carried out, because [why]; its continuation is handed
/// [Refused] with that reason.
final class Deny extends Decision {
  const Deny(this.why);

  final String why;
}

/// What became of a [Run].
sealed class Outcome<O> {
  const Outcome();
}

/// It ran, and gave [output].
final class Ran<O> extends Outcome<O> {
  const Ran(this.output);

  final O output;
}

/// It did not run: the airlock denied it, its driver refused it (a path that
/// leaves the tree), or the home has no driver for its program. An [Outcome]
/// of every program, since [Never] is a subtype of every type.
final class Refused extends Outcome<Never> {
  const Refused(this.why);

  final String why;
}

/// A program a home may run: what it takes, [I], and what it gives back, [O].
///
/// Some the home implements itself, with typed inputs ([ReadFile],
/// [WriteFile]); others it only starts, with plain arguments ([Executable]).
/// Anyone may define one. A program finds the driver it needs through
/// [Cleared], and a home without that driver cannot run it.
abstract class Program<I, O> {
  const Program();

  static const read = ReadFile();
  static const write = WriteFile();

  /// For the model and the record; never compared.
  String get name;

  /// A run of this program on [input], continuing with [then].
  Run<A> run<A>(
    I input, {
    required Result<A> Function(Outcome<O> outcome) then,
  }) => _Run(this, input, then);

  /// A run whose refusal is the tool's failure: [then] is called only with
  /// the output.
  Run<A> runOrRefusal<A>(
    I input, {
    required Result<A> Function(O output) then,
  }) => _Run(
    this,
    input,
    (outcome) => switch (outcome) {
      Ran(:final output) => then(output),
      Refused(:final why) => Failed(why),
    },
  );

  /// [input] performed by the driver [cleared] finds for this program, or
  /// null when the home has none.
  ///
  /// Called by [Run.next] alone, since only it makes a [Cleared].
  Future<Outcome<O>>? on(Cleared cleared, I input);
}

/// A run the airlock allowed, in the home it runs in: what a [Program] is
/// given to carry out its input.
///
/// Made only by [Run.next], once the [Airlock] has allowed the run, so a
/// program can be carried out only after a decision.
final class Cleared {
  Cleared._(this._home);

  final Home _home;

  /// The home's driver of kind [D], or null when it loaded none.
  D? driver<D extends Driver>() => _home._drivers.whereType<D>().firstOrNull;
}

/// What a home can do: the drivers it loaded. A program it has no driver
/// for is refused, so a home that loads no [ProgramDriver], such as a
/// phone's, starts nothing.
///
/// Its drivers are reached only through [Cleared], so holding a home is not
/// a way to carry out a run.
final class Home {
  Home(Iterable<Driver> drivers) : _drivers = List.unmodifiable(drivers);

  final List<Driver> _drivers;
}

/// Operates one part of the world, for the programs that need it.
abstract interface class Driver {}

/// Reads and writes files in the home's tree.
abstract interface class FileDriver implements Driver {
  Future<Outcome<ReadResult>> read(String path);
  Future<Outcome<Wrote>> write(FileText file);
}

/// Starts programs as processes.
abstract interface class ProgramDriver implements Driver {
  Future<Outcome<ExecResult>> start(Executable program, Args args);
}

/// Reads the file at a path, relative to the tree's root.
final class ReadFile extends Program<String, ReadResult> {
  const ReadFile();

  @override
  String get name => 'read';

  @override
  Future<Outcome<ReadResult>>? on(Cleared cleared, String path) =>
      cleared.driver<FileDriver>()?.read(path);
}

/// Writes a file, creating its directory.
final class WriteFile extends Program<FileText, Wrote> {
  const WriteFile();

  @override
  String get name => 'write';

  @override
  Future<Outcome<Wrote>>? on(Cleared cleared, FileText file) =>
      cleared.driver<FileDriver>()?.write(file);
}

/// A program the home starts as a process, such as `git`: its input is
/// plain arguments, and it reaches whatever the process can.
final class Executable extends Program<Args, ExecResult> {
  const Executable(this.name);

  @override
  final String name;

  @override
  Future<Outcome<ExecResult>>? on(Cleared cleared, Args args) =>
      cleared.driver<ProgramDriver>()?.start(this, args);
}

/// [text] for the file at [path], relative to the tree's root. [path] is as
/// the tool was given it; the driver decides whether it may be written.
final class FileText {
  const FileText(this.path, this.text);

  final String path;
  final String text;
}

/// What an [Executable] is given.
final class Args {
  const Args(this.args, {this.stdin, this.inSubdir});

  final List<String> args;

  /// Written to the program's stdin, then closed. Null: stdin is closed at
  /// once.
  final String? stdin;

  /// Where it runs, relative to the tree's root; null for the root.
  final String? inSubdir;
}

/// What a [ReadFile] found.
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

/// What an [Executable] did once it started.
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
