import 'dart:async';

import 'path_in_repo.dart';
import 'values.dart';

/// What a tool's code returns for a call: a run whose outcome it needs
/// before it can answer, its answer, or that it could not answer. [A] is the
/// type of the answer, the tool's output type.
///
/// A tool holds no driver and touches nothing. Its result is followed on a
/// [JourneyPath], which has each run decided, recorded and carried out, and
/// gives what became of it to the run's continuation. So a tool can describe
/// nothing a run cannot express.
///
/// Not an [Outcome], which is what happened to one run. A [Run] never reaches
/// the model: [Done]'s value does, rendered by the tool's definition, and
/// [Failed]'s reason does, as an error.
sealed class Result<A> {
  const Result();
}

/// Run a program on an input, then continue with what became of the run.
///
/// The one effect a tool can describe. A read, a write and `git diff` are all
/// runs, of one of three programs.
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

  /// What this run would do to the world, for the airlock's decision and
  /// record.
  Reach get reach;

  /// This run carried out on [journeyPath], and the result it leads to.
  ///
  /// The only way to carry out a run. The journey path's airlock decides it,
  /// and records the decision before any driver is reached; an allowed run
  /// is carried out by a driver of the journey path; the airlock records
  /// what became of it before the continuation sees it. If either record
  /// cannot be written, its error ends the call: no driver is reached
  /// without a recorded decision, and no outcome flows on unrecorded.
  Future<Result<A>> next(JourneyPath<Object?> journeyPath);
}

/// A [Run] of a [Program] taking [I] and giving [O].
///
/// Made only by its program ([Program.run], [Program.runOrRefusal]), so [I]
/// is the program's own input type. Built from a program and an input side
/// by side, inference would widen [I] to fit both, and a [WriteFile] given a
/// `String` would compile.
final class _Run<I, O, A> extends Run<A> {
  const _Run(this._program, this._input, this._then) : super._();

  final Program<I, O> _program;
  final I _input;
  final Result<A> Function(Outcome<O> outcome) _then;

  @override
  Reach get reach => _program._reach(_input);

  @override
  Future<Result<A>> next(JourneyPath<Object?> journeyPath) async =>
      _then(await journeyPath._carryOut(this));
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

/// A program a run may carry out: what it takes, [I], and what it gives
/// back, [O].
///
/// A closed set: [ReadFile], [WriteFile] and [Executable]. Programs reach
/// drivers, so they are part of what is trusted, with the drivers and the
/// airlock; a new kind of effect is a new driver and program here.
sealed class Program<I, O> {
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

  Reach _reach(I input);

  /// [input] performed by [journeyPath]'s driver for this program, or null
  /// when it has none.
  Future<Outcome<O>>? _on(JourneyPath<Object?> journeyPath, I input);
}

/// Reads the file at a path in the repo.
final class ReadFile extends Program<PathInRepo, ReadResult> {
  const ReadFile();

  @override
  String get name => 'read';

  @override
  Reach _reach(PathInRepo path) => Reads(path);

  @override
  Future<Outcome<ReadResult>>? _on(
    JourneyPath<Object?> journeyPath,
    PathInRepo path,
  ) => journeyPath._driver<FileDriver>()?.read(path);
}

/// Writes a file, creating its folder.
final class WriteFile extends Program<FileText, Wrote> {
  const WriteFile();

  @override
  String get name => 'write';

  @override
  Reach _reach(FileText file) => Writes(file);

  @override
  Future<Outcome<Wrote>>? _on(
    JourneyPath<Object?> journeyPath,
    FileText file,
  ) => journeyPath._driver<FileDriver>()?.write(file);
}

/// A program started as a process, such as `git`: its input is plain
/// arguments, and it reaches whatever the process can.
final class Executable extends Program<Args, ExecResult> {
  const Executable(this.name);

  @override
  final String name;

  @override
  Reach _reach(Args args) => Starts(this, args);

  @override
  Future<Outcome<ExecResult>>? _on(
    JourneyPath<Object?> journeyPath,
    Args args,
  ) => journeyPath._driver<ProgramDriver>()?.start(this, args);
}

/// What a run would do to the world, typed, so the airlock can decide and
/// record it without knowing the run's types: one per [Program].
sealed class Reach {
  const Reach();
}

final class Reads extends Reach {
  const Reads(this.path);

  final PathInRepo path;
}

final class Writes extends Reach {
  const Writes(this.file);

  final FileText file;
}

final class Starts extends Reach {
  const Starts(this.program, this.args);

  final Executable program;
  final Args args;
}

/// Operates one part of the world, for the programs that need it. A machine
/// loads the drivers it can run: a phone's loads no [ProgramDriver].
abstract interface class Driver {}

/// Reads and writes files in the journey's working tree.
abstract interface class FileDriver implements Driver {
  Future<Outcome<ReadResult>> read(PathInRepo path);
  Future<Outcome<Wrote>> write(FileText file);
}

/// Starts programs as processes.
abstract interface class ProgramDriver implements Driver {
  Future<Outcome<ExecResult>> start(Executable program, Args args);
}

/// One agent's own journey: the thread its runs are carried out on, with
/// rules [R] that say what it may do.
///
/// Its apex is its growing tip, where its next effect happens; two agents on
/// one machine have two apexes. Its drivers are those of the machine its apex
/// is on, acting as the journey's user, and are reached only by a [Run]
/// carried out on it, so every such run passes its airlock.
///
/// Started by whoever holds the drivers ([JourneyPath.start]), which is
/// already the power to touch the world, so starting one grants nothing
/// new. Everyone else gets journey paths by [narrowed], which gives no more
/// than the journey path it came from.
final class JourneyPath<R> {
  JourneyPath._(
    this.id,
    this.rules,
    this._airlock,
    this._drivers,
    this._parent,
  );

  /// A journey path named [id], on [drivers], decided and recorded by
  /// [airlock], under [rules].
  JourneyPath.start({
    required JourneyPathId id,
    required Iterable<Driver> drivers,
    required Airlock<R> airlock,
    required R rules,
  }) : this._(id, rules, airlock, List.unmodifiable(drivers), null);

  /// Names this journey path in every entry it records.
  final JourneyPathId id;
  final R rules;
  final Airlock<R> _airlock;
  final List<Driver> _drivers;
  final JourneyPath<R>? _parent;
  final _entries = StreamController<Entry>.broadcast(sync: true);
  bool _stopped = false;

  /// A journey path named [id], under [fewer] rules, on the same drivers and
  /// airlock, or null when the airlock finds [fewer] allows more than
  /// [rules]. Stopped when this one is.
  JourneyPath<R>? narrowed(R fewer, {required JourneyPathId id}) =>
      _airlock.narrows(fewer, rules)
      ? JourneyPath._(id, fewer, _airlock, _drivers, this)
      : null;

  /// Refuses every run not yet carried out, on this journey path and every
  /// one narrowed from it. A run whose driver has already been reached is
  /// not interrupted.
  void stop() => _stopped = true;

  bool get stopped => _stopped || (_parent?.stopped ?? false);

  /// Each entry once the airlock has recorded it, from this journey path and
  /// every one narrowed from it.
  Stream<Entry> get entries => _entries.stream;

  D? _driver<D extends Driver>() => _drivers.whereType<D>().firstOrNull;

  Future<Outcome<O>> _carryOut<I, O>(_Run<I, O, Object?> run) async {
    var decision = stopped
        ? const Deny('stopped')
        : await _airlock.decide(run, rules);
    if (stopped) decision = const Deny('stopped');
    await _record(Decided(id, run, decision));
    final Outcome<O> outcome = switch (decision) {
      Deny(:final why) => Refused(why),
      Allow() =>
        await run._program._on(this, run._input) ??
            Refused('this machine cannot run ${run._program.name}'),
    };
    await _record(Settled(id, run, outcome));
    return outcome;
  }

  Future<void> _record(Entry entry) async {
    await _airlock.record(entry);
    for (JourneyPath<R>? p = this; p != null; p = p._parent) {
      p._entries.add(entry);
    }
  }
}

/// Decides each run on a journey path, and records it.
///
/// What intersyntactic's airlock implements. It guards the drivers it is
/// started with, not the journey: an agent that joins a journey with its own
/// drivers is decided, or not, by its own.
abstract interface class Airlock<R> {
  /// Whether [run] may be carried out under [rules].
  Future<Decision> decide(Run<Object?> run, R rules);

  /// Whether [fewer] allows nothing that [rules] does not.
  bool narrows(R fewer, R rules);

  /// Keeps [entry]. A run's driver is reached only once its [Decided] entry
  /// is kept, and its outcome flows on only once its [Settled] entry is; an
  /// error thrown here ends the call.
  Future<void> record(Entry entry);
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

/// What names a journey path in the record, so its entries can be told from
/// those of every other journey path in the journey, after a restart too.
///
/// Given by whoever starts or narrows the journey path, which is the code
/// that knows what it is naming; keeping it unique within the journey is
/// theirs.
final class JourneyPathId {
  const JourneyPathId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is JourneyPathId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// One entry in a journey path's record: [Decided] before a run, [Settled]
/// after it.
sealed class Entry {
  const Entry(this.journeyPathId, this.run);

  /// The journey path [run] was carried out on.
  final JourneyPathId journeyPathId;
  final Run<Object?> run;
}

/// [run] was decided, and no driver has been reached yet. Without a
/// [Settled] entry after it, the record shows the run was cut short.
final class Decided extends Entry {
  const Decided(super.journeyPathId, super.run, this.decision);

  final Decision decision;
}

/// What became of [run].
final class Settled extends Entry {
  const Settled(super.journeyPathId, super.run, this.outcome);

  final Outcome<Object?> outcome;
}
