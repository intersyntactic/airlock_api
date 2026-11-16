import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:is_content_id/is_content_id.dart' show ObjectId;
import 'package:is_effects/is_effects.dart';
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, EntryId, JourneyPathId, RendererId;

part 'path_started.dart';
part 'post_entries.dart';
part 'proposal.dart';

/// What a tool's code returns for a call: a run whose outcome it needs
/// before it can answer, its answer, or that it could not answer. [A] is the
/// type of the answer, the tool's output type.
///
/// A tool holds no driver and touches nothing. Its result is followed at an
/// [Apex], whose journey path has each run decided and recorded, and reached
/// by a driver if it is allowed, and gives what became of it to the run's
/// continuation. So a tool can
/// describe nothing a run cannot express.
///
/// Not an [Outcome], which is what happened to one run. A [Run] never reaches
/// the model: [Done]'s value does, rendered by the tool's definition, and
/// [Failed]'s reason does, as an error.
sealed class Result<A> {
  const Result();

  /// This result with its answer, once there is one, given to [f].
  ///
  /// Reaches no driver: a run's continuation is extended, so [f] is applied
  /// when a later [Run.next] reaches an answer, and every run on the way is
  /// still decided and recorded. So whoever turns a tool's answer into what
  /// the model is told can do it without following the runs.
  Result<B> map<B>(B Function(A answer) f);
}

/// Run a program on an input, then continue with what became of the run.
///
/// The one effect a tool can describe. A read, a write, `git diff` and a post
/// to a chat are all runs, of one of four programs.
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

  /// This run proposed at [apex], and the result it leads to.
  ///
  /// The only way a run reaches the world. What it would do, its [Reach], is
  /// worked out first; the journey path's airlock decides it, and records
  /// the decision, at the apex's place, before any driver is reached; a
  /// driver of the journey path carries out an allowed run;
  /// the airlock records what became of it before the continuation sees it.
  /// If either record cannot be written, its error ends the call: no driver
  /// is reached without a recorded decision, and no outcome flows on
  /// unrecorded.
  Future<Result<A>> next(Apex apex);

  @override
  Run<B> map<B>(B Function(A answer) f);
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
  Future<Result<A>> next(Apex apex) async =>
      _then(await apex._propose(_program, _input));

  @override
  Run<B> map<B>(B Function(A answer) f) =>
      _Run(_program, _input, (outcome) => _then(outcome).map(f));
}

/// The tool's answer. [value] reaches the model as its definition's
/// `Output` renders it.
final class Done<A> extends Result<A> {
  const Done(this.value);

  final A value;

  @override
  Done<B> map<B>(B Function(A answer) f) => Done(f(value));
}

/// The tool could not answer, because [why]. A [Result] of every tool, since
/// [Never] is a subtype of every type; the model is told [why] as an error.
final class Failed extends Result<Never> {
  const Failed(this.why);

  final String why;

  /// Itself: there is no answer to give [f].
  @override
  Failed map<B>(B Function(Never answer) f) => this;
}

/// A program a run may be of: what it takes, [I], and what it gives
/// back, [O].
///
/// A closed set: [ReadFile], [WriteFile], [Executable] and [WebPost].
/// Programs reach drivers, so they are part of what is trusted, with the
/// drivers and the airlock; a new kind of effect is a new driver and program
/// here.
///
/// A journey path's prompts are not programs: the model is the agent
/// planning, so a prompt is not decided, and no tool is in it. How it is
/// sent and recorded is not this contract's.
sealed class Program<I, O> {
  const Program();

  static const read = ReadFile();
  static const write = WriteFile();
  static const web = WebPost();

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

  /// What [input] would do to the world. Only a post asks [findRenderer]
  /// for the renderer it names.
  Future<Reach> _reach(I input, _FindRenderer findRenderer);

  /// How this program, its input and its output travel between the agent
  /// loop and the airlock.
  _Wire<I, O> get _wire;

  /// This program with the input [json] holds. Throws a [FormatException]
  /// when it holds none.
  _Work<I, O> _work(Object? json) =>
      _Work(this, _wire.inputFromJson(json, 'input'));

  /// [input], whose reach is [reach], performed by [journeyPath]'s driver
  /// for this program, reporting to [report] while it runs, or null when it
  /// has none. Only a post waits on [rendered], for its body.
  Future<Outcome<O>>? _on(
    JourneyPath<Object?, Object?> journeyPath,
    I input,
    Reach reach,
    _Rendered rendered,
    Report report,
  );
}

/// The renderer a name names, or null: [Airlock.renderer].
typedef _FindRenderer = Future<Renderer?> Function(RendererName name);

/// The body a renderer recorded for this run's [Decided] entry, or why
/// there is none: [Airlock.rendered].
typedef _Rendered = Future<Outcome<String>> Function();

/// Reads the file at a path under the file driver's root.
final class ReadFile extends Program<RelativePath, ReadResult> {
  const ReadFile();

  @override
  String get name => 'read';

  @override
  Future<Reach> _reach(RelativePath path, _FindRenderer findRenderer) async =>
      Reads(path);

  @override
  _Wire<RelativePath, ReadResult> get _wire => const _Wire(
    {'program': 'read'},
    inputToJson: encodeRelativePath,
    inputFromJson: decodeRelativePath,
    outputToJson: encodeReadResult,
    outputFromJson: decodeReadResult,
  );

  @override
  Future<Outcome<ReadResult>>? _on(
    JourneyPath<Object?, Object?> journeyPath,
    RelativePath path,
    Reach reach,
    _Rendered rendered,
    Report report,
  ) => journeyPath._driver<FileDriver>()?.read(path);
}

/// Writes a file, creating its folder.
final class WriteFile extends Program<FileText, Wrote> {
  const WriteFile();

  @override
  String get name => 'write';

  @override
  Future<Reach> _reach(FileText file, _FindRenderer findRenderer) async =>
      Writes(file);

  @override
  _Wire<FileText, Wrote> get _wire => const _Wire(
    {'program': 'write'},
    inputToJson: encodeFileText,
    inputFromJson: decodeFileText,
    outputToJson: encodeWrote,
    outputFromJson: decodeWrote,
  );

  @override
  Future<Outcome<Wrote>>? _on(
    JourneyPath<Object?, Object?> journeyPath,
    FileText file,
    Reach reach,
    _Rendered rendered,
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
  Future<Reach> _reach(Args args, _FindRenderer findRenderer) async =>
      Starts(program, args);

  @override
  _Wire<Args, ExecResult> get _wire => _Wire(
    {'program': 'start', 'executable': program.value},
    inputToJson: encodeArgs,
    inputFromJson: decodeArgs,
    outputToJson: encodeExecResult,
    outputFromJson: decodeExecResult,
  );

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
    Reach reach,
    _Rendered rendered,
    Report report,
  ) => journeyPath._driver<ProgramDriver>()?.start(
    program,
    args,
    report: report,
  );
}

/// Sends a [Post] to a site, through the sign-in it names, with the body
/// its renderer drew from recorded entries and recorded.
///
/// An effect, decided like any other: what a tool posts to a chat, an issue
/// tracker or an API. Not a prompt, which is the agent planning and is not
/// decided.
///
/// The renderer is named exactly before the decision, so the [Decided]
/// entry says which code will write the words. The renderer follows the
/// journal for that entry, draws the body, and records it; the airlock sends
/// what was recorded. So the words exist only once the decision is kept,
/// the exact bytes sent are in the record, and the airlock never talks to a
/// renderer (https://github.com/enspyrco/intersyntactic/issues/1147#issuecomment-6905923566).
final class WebPost extends Program<Post, Sent> {
  const WebPost();

  @override
  String get name => 'web';

  @override
  Future<Reach> _reach(Post post, _FindRenderer findRenderer) async =>
      Sends(post, await findRenderer(post.renderer));

  @override
  _Wire<Post, Sent> get _wire => const _Wire(
    {'program': 'web'},
    inputToJson: _postToJson,
    inputFromJson: _postFromJson,
    outputToJson: encodeSent,
    outputFromJson: decodeSent,
  );

  @override
  Future<Outcome<Sent>>? _on(
    JourneyPath<Object?, Object?> journeyPath,
    Post post,
    covariant Sends reach,
    _Rendered rendered,
    Report report,
  ) => switch ((journeyPath._driver<WebDriver>(), reach.renderer)) {
    (null, _) => null,
    (final web?, _?) => _send(web, rendered(), post),
    // Decided as a denial before any driver, so not reached.
    (_, null) => Future.value(Refused('no renderer named ${post.renderer}')),
  };

  static Future<Outcome<Sent>> _send(
    WebDriver web,
    Future<Outcome<String>> rendering,
    Post post,
  ) async => switch (await rendering) {
    Refused(:final why) => Refused(why),
    Ran(output: final body) => await web.send(
      Request(
        post.origin,
        method: post.method,
        path: post.path,
        signIn: post.signIn,
        headers: post.headers,
        body: body,
      ),
    ),
  };
}

/// What a tool posts: where to, as whom, and which recorded entries the
/// words are drawn from, by which renderer. It holds no words of its own,
/// so a tool cannot put any in a post.
///
/// [path] and [headers] are checked as is_effects's `Request` checks them:
/// a [WebPath] cannot name another site, and [headers] hold no credential.
final class Post {
  Post(
    this.origin, {
    required this.renderer,
    Iterable<EntryId> entries = const [],
    this.method = Method.post,
    this.path = WebPath.root,
    this.signIn,
    Map<String, String> headers = const {},
  }) : entries = List.unmodifiable(entries),
       headers = validatedHeaders(headers);

  final Origin origin;
  final Method method;
  final WebPath path;

  /// Who it goes as; null sends under no sign-in.
  final SignIn? signIn;
  final Map<String, String> headers;

  /// The renderer that draws the body, by name.
  final RendererName renderer;

  /// The recorded entries the body is drawn from, in the order the renderer
  /// is given them: turns, events, the airlock's own entries, chunks of a
  /// reply. Any one the journal does not hold refuses the post.
  final List<EntryId> entries;
}

/// A renderer's name, such as `teams-reply`: what a [Post] names, and the
/// airlock resolves to the exact [Renderer] before deciding it.
final class RendererName {
  const RendererName._(this.value);

  /// [raw] as a renderer's name, or null unless it is lowercase letters,
  /// digits and `-`, starting with a letter.
  static RendererName? parse(String raw) =>
      _rendererName.hasMatch(raw) ? RendererName._(raw) : null;

  final String value;

  @override
  bool operator ==(Object other) =>
      other is RendererName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final _rendererName = RegExp(r'^[a-z][a-z0-9-]*$');

/// A renderer named exactly: [id], its source, and [executable], the
/// follower built with it.
///
/// [id] names the renderer proper, a package whose `lib/` is only the pure
/// function from entries to a body, which a person can read and check.
/// [executable] names the follower built with it: the one shared program
/// that follows the journal, reads the entries and writes [Rendered],
/// compiled once per renderer with [id] as a define, which it reports in
/// [Rendered.renderer]. Since the define is compiled in, each renderer's
/// follower has its own build, and that build is what the journal's writer
/// approves. Both are recorded in the [Decided] entry, so an old post can be
/// rebuilt from the journal and checked
/// (https://github.com/enspyrco/intersyntactic/issues/1147).
final class Renderer {
  const Renderer(this.id, {required this.executable});

  final RendererId id;

  /// The journal object holding the follower's bytes, built with [id].
  final ObjectId executable;
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

/// Reaches the world: a request goes to [origin], as [signIn], or under no
/// sign-in when null.
///
/// Null means no sign-in, never any: it is null exactly when the request
/// has none. So a rule granting a site under no sign-in must not match
/// a send that has one, or a grant to fetch a page anonymously would let a
/// journey path post there as a bot.
///
/// A rule grants the origin and the sign-in together, never the origin
/// alone: every bot of a kind posts to the same sites, so a grant by origin
/// would let a journey path send as any sign-in the web driver holds.
///
/// Holds the whole [post] and the [renderer] its name resolved to, never a
/// body, which does not exist yet when this is decided: the record says
/// which entries the words were drawn from and which code drew them, so it
/// holds no copy of what was said.
final class Sends extends Reach {
  const Sends(this.post, this.renderer);

  final Post post;

  /// The exact renderer [post] names, or null when its name named none on
  /// this machine. A send with no renderer is denied before the rules are
  /// asked, since there would be no way to draw its words.
  final Renderer? renderer;

  Origin get origin => post.origin;
  SignIn? get signIn => post.signIn;
}

/// One agent's own journey: the thread its runs are proposed on, with
/// rules [R] that say what it may do, and places [P] that say where in a
/// turn each entry happened.
///
/// Its drivers are those it was given, acting as the journey's user, each
/// wherever it runs. They are reached only by a [Run] proposed at one of its
/// apexes, so every such run passes its airlock.
///
/// This is the airlock service's side of a journey path, set up when
/// loop_launcher says the docking port has started the path
/// ([PathStarted]). The airlock
/// starts nothing. Whoever holds the drivers already has the power to touch
/// the world, so setting up a side grants nothing new.
final class JourneyPath<R, P> {
  /// The side of the journey path named [id], on [drivers], decided and
  /// recorded by [airlock], under [rules].
  ///
  /// [id] is the hash of the record entry that started the path, which the
  /// docking port writes, so no two journey paths share one and nothing here
  /// mints one.
  JourneyPath({
    required this.id,
    required Iterable<Driver> drivers,
    required this._airlock,
    required this.rules,
  }) : _drivers = List.unmodifiable(drivers);

  /// Names this journey path in every entry it records.
  final JourneyPathId id;
  final R rules;
  final Airlock<R, P> _airlock;
  final List<Driver> _drivers;
  final _entries = StreamController<Entry<P>>.broadcast(sync: true);
  final _underway = StreamController<Underway<P>>.broadcast(sync: true);
  bool _stopped = false;

  /// What this journey path's agent loop puts in each [Proposal], to show it
  /// is that loop: minted here, and handed only to loop_launcher, which
  /// launches the loop.
  PathToken get token => _token;
  PathToken _token = PathToken._mint();

  /// A new [token], in place of the old one, which is rejected from then
  /// on: for a [PathStarted] naming a path whose side is already set up,
  /// when loop_launcher has restarted and lost the token. Only one loop
  /// holds a path's token.
  PathToken reissue() => _token = PathToken._mint();

  /// This journey path's tip at [place], where its runs are proposed in this
  /// process.
  ///
  /// Here, where [P] is known, so a place of another type does not compile;
  /// whoever is handed the apex never sees [P].
  Apex at(P place) => _AtPath(this, place);

  /// Refuses every run on this journey path whose driver has not yet been
  /// reached. A run whose driver has been reached is not interrupted. Never
  /// undone: a [PathStarted] that says the path is not stopped leaves it
  /// stopped.
  void stop() => _stopped = true;

  bool get stopped => _stopped;

  /// Each entry once the airlock has recorded it.
  Stream<Entry<P>> get entries => _entries.stream;

  /// What drivers report while runs are underway: for a live view, and not
  /// recorded.
  Stream<Underway<P>> get underway => _underway.stream;

  D? _driver<D extends Driver>() => _drivers.whereType<D>().firstOrNull;

  Future<Outcome<O>> _consider<I, O>(
    Program<I, O> program,
    I input,
    P place,
  ) async {
    const stoppedByPerson = Deny('stopped', by: DecidedBy.person);
    final reach = await program._reach(input, _airlock.renderer);
    var decision = switch (reach) {
      _ when stopped => stoppedByPerson,
      Sends(renderer: null, :final post) => Deny(
        'no renderer named ${post.renderer}',
        by: DecidedBy.rules,
      ),
      _ => await _airlock.decide(reach, rules),
    };
    if (stopped) decision = stoppedByPerson;
    final decided = Decided(id, place, reach, decision);
    await _record(decided);
    final Outcome<O> outcome = switch (decision) {
      Deny(:final why) => Refused(why),
      Allow() =>
        await program._on(
              this,
              input,
              reach,
              () => _airlock.rendered(decided),
              (progress) => _underway.add(Underway(id, place, reach, progress)),
            ) ??
            Refused('this machine cannot run ${program.name}'),
    };
    await _record(Returned(id, place, reach, outcome));
    return outcome;
  }

  Future<void> _record(Entry<P> entry) async {
    await _airlock.record(entry);
    _entries.add(entry);
  }

  /// [proposal] considered at [place], as a run proposed at [at]'s apex
  /// would be, once it shows this path's [token]: decided and recorded, and
  /// carried out by a driver if it is allowed. A proposal of another journey
  /// path, or with another token, is [Rejected] and recorded in no journey
  /// path's record.
  ///
  /// [place] is [Proposal.place] read as a [P] by the service, which knows
  /// [P].
  Future<ProposalAnswer> consider(Proposal proposal, P place) async {
    if (proposal.journeyPath != id) {
      return const Rejected('another journey path');
    }
    if (!token._matches(proposal.token)) {
      return const Rejected("not this journey path's token");
    }
    return Considered._(await proposal._work.on(this, place));
  }
}

/// A journey path's tip at one place in a turn: where its agent loop
/// proposes the next run and its airlock decides it, recording each entry
/// at that place.
///
/// Made by [JourneyPath.at] where the journey path is, in the airlock
/// service, and by [Apex.through] in the agent loop, which is another
/// process: there a run's program and input go to the airlock as a
/// [Proposal], and its continuation stays behind, since it is the tool's own
/// code. Either
/// way, what follows a tool's result takes an apex and never handles the
/// place. Two agents on one machine have two apexes; one step's two tool
/// calls are two apexes of one journey path, at two places.
sealed class Apex {
  const Apex();

  /// The apex at [place] on the journey path [journeyPath], reached through
  /// [link], showing [token] to say this is that path's loop.
  ///
  /// [place] is already the JSON its journey path reads places from, since
  /// the loop and the airlock service agree its type between them.
  const factory Apex.through(
    AirlockLink link, {
    required JourneyPathId journeyPath,
    required PathToken token,
    required Object? place,
  }) = _ThroughLink;

  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input);
}

final class _AtPath<P> extends Apex {
  const _AtPath(this._journeyPath, this._place);

  final JourneyPath<Object?, P> _journeyPath;
  final P _place;

  @override
  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input) =>
      _journeyPath._consider(program, input, _place);
}

/// Decides each run on a journey path, and records it.
///
/// What intersyntactic's airlock implements. It guards the drivers it is
/// given, not the journey: an agent that joins a journey with its own
/// drivers is decided, or not, by its own.
abstract interface class Airlock<R, P> {
  /// Whether a driver may carry out a run that would do [reach], under
  /// [rules].
  ///
  /// Given the reach, not the run, so the decision is about exactly what is
  /// recorded: for a post, the renderer its name resolved to.
  Future<Decision> decide(Reach reach, R rules);

  /// Keeps [entry]. A run's driver is reached only once its [Decided] entry
  /// is kept, and its outcome flows on only once its [Returned] entry is; an
  /// error thrown here ends the call.
  ///
  /// Kept means it survives the journal crashing or being killed, not a
  /// power cut: the journal answers before forcing the entry to disk, and a
  /// power cut can leave an entry with missing bytes, which its `check()`
  /// reports. So "no driver is reached without a recorded [Decided]" holds
  /// across crashes (https://github.com/intersyntactic/journal/pull/12).
  Future<void> record(Entry<P> entry);

  /// The renderer called [name], or null when there is none, so the
  /// [Decided] entry for a post names its renderer exactly.
  Future<Renderer?> renderer(RendererName name);

  /// The body the renderer recorded for [decided], an allowed post's
  /// [Decided] entry, once the airlock has followed the journal to it; or
  /// [Refused] with why there is none.
  ///
  /// Called only after [decided] is kept. The renderer follows the journal
  /// for it, reads the entries the post draws from, and records the body,
  /// or a refusal when an entry is missing or fails its checks, in an entry
  /// of its own following [decided]. The airlock never talks to a renderer:
  /// it reads that entry, and accepts it only from the renderer [decided]
  /// names. A renderer that does not answer in time is the airlock's to
  /// refuse, and its [Returned] entry then follows [decided] instead.
  ///
  /// The renderer reports the source it was built from, the `FileSetId` it
  /// was given as a define at compile time (as is_journal's
  /// `Journal.builtDefine` gives a journal its code hash), and an entry
  /// whose renderer reports anything other than the id [decided] names is
  /// refused. That rules out a stale or mis-built renderer being taken for
  /// this one, not someone building one that lies.
  Future<Outcome<String>> rendered(Decided<P> decided);
}

/// What the [Airlock] decided about one run, and [by] whom, so the record
/// tells "the rules let it through" from "the person said yes".
sealed class Decision {
  const Decision({required this.by});

  final DecidedBy by;
}

/// A driver may carry the run out.
final class Allow extends Decision {
  const Allow({required super.by});
}

/// No driver carries the run out, because [why]; its continuation is handed
/// [Refused] with that reason.
final class Deny extends Decision {
  const Deny(this.why, {required super.by});

  final String why;
}

/// One entry in a journey path's record: [Decided] before a run goes out,
/// and [Returned] when it comes back.
///
/// Each is at a [place] in a turn, of type [P], which the agent loop
/// supplies, since it knows where in the turn it is, and the airlock
/// records; nothing here computes one.
///
/// Every kind takes [P] and nothing more, so a switch over the kinds is
/// exhaustive: a kind with a type parameter its parent does not have cannot
/// be covered by a case.
sealed class Entry<P> {
  const Entry(this.journeyPathId, this.place);

  /// The journey path this entry is of.
  final JourneyPathId journeyPathId;

  /// Where in a turn this entry happened.
  final P place;
}

/// A run that would do [reach] was decided, and no driver has been reached
/// yet. Without a [Returned] entry after it, the record shows the run was
/// cut short.
final class Decided<P> extends Entry<P> {
  const Decided(super.journeyPathId, super.place, this.reach, this.decision);

  final Reach reach;
  final Decision decision;
}

/// The run that would do [reach] came back, with its [outcome], whether it
/// ran or was refused.
final class Returned<P> extends Entry<P> {
  const Returned(super.journeyPathId, super.place, this.reach, this.outcome);

  final Reach reach;
  final Outcome<Object?> outcome;
}

/// What a driver reported, [progress], while the run doing [reach] was
/// underway at [place] on the journey path named [journeyPathId].
final class Underway<P> {
  const Underway(this.journeyPathId, this.place, this.reach, this.progress);

  final JourneyPathId journeyPathId;
  final P place;
  final Reach reach;
  final Progress progress;
}
