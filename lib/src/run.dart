import 'dart:async';

import 'package:is_effects/is_effects.dart';

/// What a tool's code returns for a call: a run whose outcome it needs
/// before it can answer, its answer, or that it could not answer. [A] is the
/// type of the answer, the tool's output type.
///
/// A tool holds no driver and touches nothing. Its result is followed at an
/// [Apex], whose journey path has each run decided, recorded and carried out,
/// and gives what became of it to the run's continuation. So a tool can
/// describe nothing a run cannot express.
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

  /// This run carried out at [apex], and the result it leads to.
  ///
  /// The only way to carry out a run. The journey path's airlock decides it,
  /// and records the decision, at the apex's place, before any driver is
  /// reached; an allowed run is carried out by a driver of the journey path;
  /// the airlock records what became of it before the continuation sees it.
  /// If either record cannot be written, its error ends the call: no driver
  /// is reached without a recorded decision, and no outcome flows on
  /// unrecorded.
  Future<Result<A>> next(Apex apex);
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
  Future<Result<A>> next(Apex apex) async =>
      _then(await apex._journeyPath._carryOut(this, apex._place));
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
/// A closed set: [ReadFile], [WriteFile], [Executable] and [WebRequest].
/// Programs reach drivers, so they are part of what is trusted, with the
/// drivers and the airlock; a new kind of effect is a new driver and program
/// here.
///
/// A journey path's prompts are not programs: the model is the agent
/// planning, so a prompt is not decided. The airlock sends it and records it
/// and what comes back, and no tool is in it, so it is the airlock's, not
/// this contract's.
sealed class Program<I, O> {
  const Program();

  static const read = ReadFile();
  static const write = WriteFile();
  static const web = WebRequest();

  /// For the model and the record; an [Executable] is compared by it.
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

  /// [input] performed by [journeyPath]'s driver for this program, reporting
  /// to [report] while it runs, or null when it has none.
  Future<Outcome<O>>? _on(
    JourneyPath<Object?, Object?> journeyPath,
    I input,
    Report report,
  );
}

/// Reads the file at a path under the file driver's root.
final class ReadFile extends Program<RelativePath, ReadResult> {
  const ReadFile();

  @override
  String get name => 'read';

  @override
  Reach _reach(RelativePath path) => Reads(path);

  @override
  Future<Outcome<ReadResult>>? _on(
    JourneyPath<Object?, Object?> journeyPath,
    RelativePath path,
    Report report,
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
    JourneyPath<Object?, Object?> journeyPath,
    FileText file,
    Report report,
  ) => journeyPath._driver<FileDriver>()?.write(file);
}

/// A program started as a process, such as `git`: its input is plain
/// arguments, and it reaches whatever the process can.
final class Executable extends Program<Args, ExecResult> {
  const Executable(this.program);

  /// [raw] as a program, or null when it is not a [ProgramName].
  static Executable? parse(String raw) => switch (ProgramName.parse(raw)) {
    final program? => Executable(program),
    null => null,
  };

  final ProgramName program;

  @override
  String get name => program.value;

  @override
  Reach _reach(Args args) => Starts(program, args);

  /// By [program], so a rule naming a program matches every run of it.
  @override
  bool operator ==(Object other) =>
      other is Executable && other.program == program;

  @override
  int get hashCode => program.hashCode;

  @override
  Future<Outcome<ExecResult>>? _on(
    JourneyPath<Object?, Object?> journeyPath,
    Args args,
    Report report,
  ) => journeyPath._driver<ProgramDriver>()?.start(
    program,
    args,
    report: report,
  );
}

/// Sends a request out of the home, through the sign-in it names, to a
/// site.
///
/// An effect, decided like any other: what a tool posts to a chat, an issue
/// tracker or an API. Not a prompt, which is the agent planning and is
/// recorded, not decided.
final class WebRequest extends Program<Request, Sent> {
  const WebRequest();

  @override
  String get name => 'web';

  @override
  Reach _reach(Request request) => Sends(request);

  @override
  Future<Outcome<Sent>>? _on(
    JourneyPath<Object?, Object?> journeyPath,
    Request request,
    Report report,
  ) => journeyPath._driver<WebDriver>()?.send(request);
}

/// What a run would do to the world, typed, so the airlock can decide and
/// record it without knowing the run's types: one per [Program].
sealed class Reach {
  const Reach();
}

final class Reads extends Reach {
  const Reads(this.path);

  final RelativePath path;
}

final class Writes extends Reach {
  const Writes(this.file);

  final FileText file;
}

final class Starts extends Reach {
  const Starts(this.program, this.args);

  final ProgramName program;
  final Args args;
}

/// Leaves the home: [request] goes to its origin, as its sign-in. A rule
/// grants a whole site by comparing the origin, and names the sign-in it
/// may go as.
final class Sends extends Reach {
  const Sends(this.request);

  final Request request;
}

/// One agent's own journey: the thread its runs are carried out on, with
/// rules [R] that say what it may do, and places [P] that say where in a
/// turn each entry happened.
///
/// Its drivers are those it was started with, acting as the journey's user,
/// each wherever it runs. They are reached only by a [Run] carried out at
/// one of its apexes, so every such run passes its airlock.
///
/// Started by whoever holds the drivers ([JourneyPath.start]), which is
/// already the power to touch the world, so starting one grants nothing
/// new. Everyone else gets journey paths by [narrowed], which gives no more
/// than the journey path it came from.
final class JourneyPath<R, P> {
  JourneyPath._(
    this.id,
    this.rules,
    this._airlock,
    this._drivers,
    this._parent,
    this._issued,
  );

  /// A journey path named [id], on [drivers], decided and recorded by
  /// [airlock], under [rules].
  JourneyPath.start({
    required JourneyPathId id,
    required Iterable<Driver> drivers,
    required Airlock<R, P> airlock,
    required R rules,
  }) : this._(id, rules, airlock, List.unmodifiable(drivers), null, {id});

  /// Names this journey path in every entry it records.
  final JourneyPathId id;
  final R rules;
  final Airlock<R, P> _airlock;
  final List<Driver> _drivers;
  final JourneyPath<R, P>? _parent;

  /// Every id asked for under the journey path this one was started from,
  /// shared by all of them.
  final Set<JourneyPathId> _issued;
  final _entries = StreamController<Entry<R, P>>.broadcast(sync: true);
  final _underway = StreamController<Underway<P>>.broadcast(sync: true);
  bool _stopped = false;

  /// This journey path's tip at [place], where its runs are carried out.
  ///
  /// Here, where [P] is known, so a place of another type does not compile;
  /// whoever is handed the apex never sees [P].
  Apex at(P place) => Apex._(this, place);

  /// A journey path named [id], under [fewer] rules, on the same drivers and
  /// airlock, or null when the airlock finds [fewer] allows more than
  /// [rules]. Stopped when this one is.
  ///
  /// Recorded either way, at [at], as a [Narrowed] entry of this journey
  /// path, before the new one exists; a refusal is an attempt to widen, and
  /// is kept.
  ///
  /// [id] must not have been asked for before under the journey path this
  /// one was started from, granted or not, or the record would mix two
  /// journey paths' entries: an [ArgumentError] when it has. Ids from before
  /// a restart are the host's to keep apart.
  ///
  /// A narrowing whose record throws has still used up [id]: whether its
  /// entry was kept is unknown, so a retry takes a new id rather than risk
  /// two entries under one.
  Future<JourneyPath<R, P>?> narrowed(
    R fewer, {
    required JourneyPathId id,
    required P at,
  }) async {
    if (!_issued.add(id)) {
      throw ArgumentError.value(id, 'id', 'names a journey path already');
    }
    final granted = _airlock.narrows(fewer, rules);
    await _record(Narrowed(this.id, at, id, fewer, granted: granted));
    return granted
        ? JourneyPath._(id, fewer, _airlock, _drivers, this, _issued)
        : null;
  }

  /// Refuses every run not yet carried out, on this journey path and every
  /// one narrowed from it. A run whose driver has already been reached is
  /// not interrupted.
  void stop() => _stopped = true;

  bool get stopped => _stopped || (_parent?.stopped ?? false);

  /// Each entry once the airlock has recorded it, from this journey path and
  /// every one narrowed from it.
  Stream<Entry<R, P>> get entries => _entries.stream;

  /// What drivers report while runs are underway, from this journey path and
  /// every one narrowed from it: for a live view, and not recorded.
  Stream<Underway<P>> get underway => _underway.stream;

  D? _driver<D extends Driver>() => _drivers.whereType<D>().firstOrNull;

  Future<Outcome<O>> _carryOut<I, O>(_Run<I, O, Object?> run, P place) async {
    const stoppedByPerson = Deny('stopped', by: DecidedBy.person);
    var decision = stopped
        ? stoppedByPerson
        : await _airlock.decide(run, rules);
    if (stopped) decision = stoppedByPerson;
    await _record(Decided(id, place, run, decision));
    final Outcome<O> outcome = switch (decision) {
      Deny(:final why) => Refused(why),
      Allow() =>
        await run._program._on(this, run._input, (progress) {
              final underway = Underway(id, place, run, progress);
              for (JourneyPath<R, P>? p = this; p != null; p = p._parent) {
                p._underway.add(underway);
              }
            }) ??
            Refused('this machine cannot run ${run._program.name}'),
    };
    await _record(Returned(id, place, run, outcome));
    return outcome;
  }

  Future<void> _record(Entry<R, P> entry) async {
    await _airlock.record(entry);
    for (JourneyPath<R, P>? p = this; p != null; p = p._parent) {
      p._entries.add(entry);
    }
  }
}

/// A journey path's tip at one place in a turn: where its agent loop and
/// airlock carry out the next run, recording each entry at that place.
///
/// Made only by [JourneyPath.at], which checks the place's type, so what
/// follows a tool's result takes an apex and never handles the place. Two
/// agents on one machine have two apexes; one step's two tool calls are two
/// apexes of one journey path, at two places.
final class Apex {
  const Apex._(this._journeyPath, this._place);

  final JourneyPath<Object?, Object?> _journeyPath;
  final Object? _place;
}

/// Decides each run on a journey path, and records it.
///
/// What intersyntactic's airlock implements. It guards the drivers it is
/// started with, not the journey: an agent that joins a journey with its own
/// drivers is decided, or not, by its own.
abstract interface class Airlock<R, P> {
  /// Whether [run] may be carried out under [rules].
  Future<Decision> decide(Run<Object?> run, R rules);

  /// Whether [fewer] allows nothing that [rules] does not.
  bool narrows(R fewer, R rules);

  /// Keeps [entry]. A run's driver is reached only once its [Decided] entry
  /// is kept, and its outcome flows on only once its [Returned] entry is; an
  /// error thrown here ends the call.
  Future<void> record(Entry<R, P> entry);
}

/// What the [Airlock] decided about one run, and [by] whom, so the record
/// tells "the rules let it through" from "the person said yes".
sealed class Decision {
  const Decision({required this.by});

  final DecidedBy by;
}

/// Who made a [Decision].
enum DecidedBy {
  /// The journey path's rules decided it.
  rules,

  /// The person was asked, or stopped the journey path.
  person,
}

/// The run may be carried out.
final class Allow extends Decision {
  const Allow({required super.by});
}

/// The run is not carried out, because [why]; its continuation is handed
/// [Refused] with that reason.
final class Deny extends Decision {
  const Deny(this.why, {required super.by});

  final String why;
}

/// What names a journey path in the record, so its entries can be told from
/// those of every other journey path in the journey, after a restart too.
///
/// Given by whoever starts or narrows the journey path, which is the code
/// that knows what it is naming. [JourneyPath.narrowed] refuses one already
/// asked for under the same started journey path.
final class JourneyPathId {
  const JourneyPathId._(this.value);

  /// [raw] as an id, or null when it is blank, which names nothing apart.
  static JourneyPathId? parse(String raw) =>
      raw.trim().isEmpty ? null : JourneyPathId._(raw);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is JourneyPathId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// One entry in a journey path's record: [Decided] before a run goes out,
/// [Returned] when it comes back, and [Narrowed] when the journey path asks
/// for a narrower one.
///
/// Each is at a [place] in a turn, of the host's type [P], which the host
/// supplies and the airlock records; nothing here computes one.
///
/// Every kind takes both the journey path's rules type [R] and [P], even
/// one that holds no rules, so a switch over the kinds is exhaustive: a
/// kind with a type parameter its parent does not have cannot be covered
/// by a case.
sealed class Entry<R, P> {
  const Entry(this.journeyPathId, this.place);

  /// The journey path this entry is of.
  final JourneyPathId journeyPathId;

  /// Where in a turn this entry happened.
  final P place;
}

/// [run] was decided, and no driver has been reached yet. Without a
/// [Returned] entry after it, the record shows the run was cut short.
final class Decided<R, P> extends Entry<R, P> {
  const Decided(super.journeyPathId, super.place, this.run, this.decision);

  final Run<Object?> run;
  final Decision decision;
}

/// [run] came back, with its [outcome], whether it ran or was refused.
final class Returned<R, P> extends Entry<R, P> {
  const Returned(super.journeyPathId, super.place, this.run, this.outcome);

  final Run<Object?> run;
  final Outcome<Object?> outcome;
}

/// What a driver reported, [progress], while [run] was underway at [place]
/// on the journey path named [journeyPathId].
final class Underway<P> {
  const Underway(this.journeyPathId, this.place, this.run, this.progress);

  final JourneyPathId journeyPathId;
  final P place;
  final Run<Object?> run;
  final Progress progress;
}

/// A journey path named [child] was asked for under [rules], and [granted]
/// when the airlock found they allow no more than this one's. The record's
/// tree of journey paths is these entries.
final class Narrowed<R, P> extends Entry<R, P> {
  const Narrowed(
    super.journeyPathId,
    super.place,
    this.child,
    this.rules, {
    required this.granted,
  });

  final JourneyPathId child;
  final R rules;
  final bool granted;
}
