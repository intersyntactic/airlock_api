import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;

import 'package:checked_json/checked_json.dart';

import 'package:is_content_id/is_content_id.dart' show ObjectId;
import 'package:is_effects/is_effects.dart';
import 'package:is_shapes/is_shapes.dart' show DecidedBy, EntryId, TrajectoryId;

part 'pool_user.dart';
part 'wire_reading.dart';
part 'proposal.dart';
part 'waiting_to_start.dart';
part 'model_request.dart';
part 'decision_entry.dart';

/// What a tool's code returns for a call: an action whose outcome it needs
/// before it can answer, its answer, or that it could not answer. [A] is the
/// type of the answer, the tool's output type.
///
/// A tool holds no driver and touches nothing. Its result is carried through
/// at a [Crux], whose trajectory has each action decided and recorded, and
/// reached by a driver if it is allowed, and gives what became of it to the
/// action's continuation. So a tool can describe nothing an action cannot
/// express.
///
/// Not an [Outcome], which is what happened to one action. An [Action] never
/// reaches the model: [Done]'s value does, written out by the tool's
/// definition, and [Failed]'s reason does, as an error.
sealed class Result<A> {
  const Result();

  /// This result with its answer, once there is one, given to [f].
  ///
  /// Reaches no driver: an action's continuation is extended, so [f] is
  /// applied when a later [Action.next] reaches an answer, and every action
  /// on the way is still decided and recorded. So whoever turns a tool's
  /// answer into what the model is told can do it without carrying out the
  /// actions.
  Result<B> map<B>(B Function(A answer) f);
}

/// Run a program on an input, then continue with what became of it.
///
/// One round trip to the world, which the airlock decides: what a tool asks
/// for to carry out an intent (Nick, 17 Nov: "the airlock sits between
/// intents and action"). A read, a write, `git diff` and a web request to a chat
/// are all actions, each one of four programs on an input, and each has
/// exactly one [Outcome].
///
/// The continuation travels with the action, not in the tool, so one tool
/// can serve concurrent calls without keeping state for any of them. It is
/// private: what it is given comes from [next], after the airlock's decision,
/// never from whoever holds the action.
///
/// Typed only by the answer it leads to, [A]. The program's input and output
/// types stay inside, where [next] uses them, so whoever holds an action
/// never handles either, and a switch over a [Result] covers every action
/// with `case Action()`. Dart's generics are covariant: a caller passing an
/// outcome to the continuation itself would be checked only when it ran.
abstract final class Action<A> extends Result<A> {
  const Action._();

  /// This action proposed at [crux], and the result it leads to.
  ///
  /// The only way an action reaches the world. What it would do, its
  /// [Reach], is worked out first; the trajectory's airlock decides it,
  /// and records the decision, at the crux's place, before any driver is
  /// reached; a driver of the trajectory carries out an allowed action;
  /// the airlock records what became of it before the continuation sees it.
  /// If either record cannot be written, its error ends the call: no driver
  /// is reached without a recorded decision, and no outcome flows on
  /// unrecorded.
  Future<Result<A>> next(Crux crux);

  @override
  Action<B> map<B>(B Function(A answer) f);
}

/// An [Action] of a [Program] taking [I] and giving [O].
///
/// Made only by its program ([Program.run], [Program.runOrRefusal]), so [I]
/// is the program's own input type. Built from a program and an input side
/// by side, inference would widen [I] to fit both, and a [WriteFile] given a
/// `String` would compile.
final class _Action<I, O, A> extends Action<A> {
  const _Action(this._program, this._input, this._then) : super._();

  final Program<I, O> _program;
  final I _input;
  final Result<A> Function(Outcome<O> outcome) _then;

  @override
  Future<Result<A>> next(Crux crux) async =>
      _then(await crux._propose(_program, _input));

  @override
  Action<B> map<B>(B Function(A answer) f) =>
      _Action(_program, _input, (outcome) => _then(outcome).map(f));
}

/// The tool's answer. [value] reaches the model as its definition's
/// `Output` writes it out.
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

/// A program an action may run: what it takes, [I], and what it gives
/// back, [O].
///
/// A closed set: [ReadFile], [ReadFileBytes], [WriteFile], [Executable],
/// [AnswerEvent], [FetchFromWeb] and [AskTheModel].
/// Programs reach drivers, so they are part of what is trusted, with the
/// drivers and the airlock; a new kind of action is a new driver and program
/// here.
///
/// A model call is one too, [AskTheModel]: the model is outside the
/// station, so the case's words leave the machine with every call
/// (https://github.com/enspyrco/intersyntactic/pull/1168, replacing the
/// ruling that the model is the agent planning and is not decided).
sealed class Program<I, O> {
  const Program();

  static const read = ReadFile();
  static const readBytes = ReadFileBytes();
  static const write = WriteFile();
  static const answerEvent = AnswerEvent();
  static const fetch = FetchFromWeb();
  static const askTheModel = AskTheModel();

  /// For the model and the record; an [Executable] is compared by it.
  String get name;

  /// The action of running this program on [input], continuing with [then].
  Action<A> run<A>(
    I input, {
    required Result<A> Function(Outcome<O> outcome) then,
  }) => _Action(this, input, then);

  /// An action whose refusal is the tool's failure: [then] is called only
  /// with the output.
  Action<A> runOrRefusal<A>(
    I input, {
    required Result<A> Function(O output) then,
  }) => _Action(
    this,
    input,
    (outcome) => switch (outcome) {
      Ran(:final output) => then(output),
      Refused(:final why) => Failed(why),
    },
  );

  /// What [input] would do to the world, as far as the input alone says.
  Reach _reach(I input);

  /// What [input] would do to the world at [place] on [trajectory], worked
  /// out before it is decided, reaching no driver; or [Refused] with why it
  /// cannot be. [_reach] for every program whose input says it all.
  Future<Outcome<Reach>> _reachOn<P>(
    Trajectory<Object?, P> trajectory,
    I input,
    P place,
  ) async => Ran(_reach(input));

  /// How this program, its input and its output travel between the agent
  /// loop and the airlock.
  _Wire<I, O> get _wire;

  /// This program with the input [json] holds. Throws a [FormatException]
  /// when it holds none.
  _Work<I, O> _work(Object? json, [String field = 'input']) =>
      _Work(this, _wire.inputFromJson(json, field));

  /// [input], whose reach is [reach], performed by [trajectory]'s driver
  /// for this program, reporting to [report] while it runs, or null when it
  /// has none.
  Future<Outcome<O>>? _on(
    Trajectory<Object?, Object?> trajectory,
    I input,
    Reach reach,
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
  _Wire<RelativePath, ReadResult> get _wire => const _Wire(
    {'program': 'read'},
    inputToJson: encodeRelativePath,
    inputFromJson: decodeRelativePath,
    outputToJson: encodeReadResult,
    outputFromJson: decodeReadResult,
  );

  @override
  Future<Outcome<ReadResult>>? _on(
    Trajectory<Object?, Object?> trajectory,
    RelativePath path,
    Reach reach,
    Report report,
  ) => trajectory._driver<ReadsAndWritesFiles>()?.read(path);
}

/// Reads the exact bytes of the file at a path under the file driver's root,
/// such as a .docx's zip. Every byte returned is recorded, so the driver
/// refuses a file over its size limit.
final class ReadFileBytes extends Program<RelativePath, BytesReadResult> {
  const ReadFileBytes();

  @override
  String get name => 'read-bytes';

  @override
  Reach _reach(RelativePath path) => Reads(path, as: ReadsAs.bytes);

  @override
  _Wire<RelativePath, BytesReadResult> get _wire => const _Wire(
    {'program': 'read-bytes'},
    inputToJson: encodeRelativePath,
    inputFromJson: decodeRelativePath,
    outputToJson: encodeBytesReadResult,
    outputFromJson: decodeBytesReadResult,
  );

  @override
  Future<Outcome<BytesReadResult>>? _on(
    Trajectory<Object?, Object?> trajectory,
    RelativePath path,
    Reach reach,
    Report report,
  ) => trajectory._driver<ReadsAndWritesFiles>()?.readBytes(path);
}

/// Writes a file, creating its folder.
final class WriteFile extends Program<FileText, Wrote> {
  const WriteFile();

  @override
  String get name => 'write';

  @override
  Reach _reach(FileText file) => Writes(file);

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
    Trajectory<Object?, Object?> trajectory,
    FileText file,
    Reach reach,
    Report report,
  ) => trajectory._driver<ReadsAndWritesFiles>()?.write(file);
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

  @override
  _Wire<Args, ExecResult> get _wire => _Wire(
    {'program': 'start', 'executable': program.value},
    inputToJson: encodeArgs,
    inputFromJson: decodeArgs,
    outputToJson: encodeExecResult,
    outputFromJson: decodeExecResult,
  );

  /// By [program], so a rule naming a program matches every action that
  /// runs it.
  @override
  bool operator ==(Object other) =>
      other is Executable && other.program == program;

  @override
  int get hashCode => program.hashCode;

  @override
  Future<Outcome<ExecResult>>? _on(
    Trajectory<Object?, Object?> trajectory,
    Args args,
    Reach reach,
    Report report,
  ) => trajectory._driver<RunsPrograms>()?.runProgram(
    program,
    args,
    report: report,
  );
}

/// The body of [entry], which must belong to [trajectory] and be of [kind],
/// as [DecidesAndRecordsActions.recordedOn] reads it; or [Refused] with why
/// not. The kind is checked, since a loop may write a body of any shape
/// under its own kinds on its own chain.
Future<Outcome<String>> _bodyOf(
  Trajectory<Object?, Object?> trajectory,
  EntryId entry,
  String kind,
) async => switch (await trajectory._airlock.recordedOn(trajectory.id, entry)) {
  Refused(:final why) => Refused(why),
  Ran(output: (kind: final recorded, :final body)) when recorded == kind => Ran(
    body,
  ),
  Ran(output: (kind: final recorded, body: _)) => Refused(
    'entry $entry is a $recorded, not a $kind',
  ),
};

/// The body of [entry], an [outcomeOfProposedActionKind] logbook entry of
/// [trajectory]'s, when the proposal it names asked the model; or [Refused]
/// with why not. Another program's result can read as a model reply, as a
/// read's `{"kind":"text","text":…}` does, so the proposal is read from the
/// trajectory's chain and checked.
Future<Outcome<String>> _modelReplyOutcome(
  Trajectory<Object?, Object?> trajectory,
  EntryId entry,
) async =>
    switch (await _bodyOf(trajectory, entry, outcomeOfProposedActionKind)) {
      Refused(:final why) => Refused(why),
      Ran(output: final recorded) => switch (readOutcomeOfProposedAction(
        recorded,
      )) {
        null => Refused('entry $entry names no proposal'),
        (:final proposed, result: _) => switch (await _bodyOf(
          trajectory,
          proposed,
          ActionProposedByAgentLoop.kind,
        )) {
          Refused(:final why) => Refused(why),
          Ran(output: final proposal) => switch (ActionProposedByAgentLoop.read(
            proposal,
          )) {
            ActionProposedByAgentLoop(program: AskTheModel()) => Ran(recorded),
            ActionProposedByAgentLoop() => Refused(
              'entry $entry answers $proposed, which asked no model',
            ),
            Rejected(:final why) => Refused(
              'entry $entry answers $proposed, which asked no model: $why',
            ),
          },
        },
      },
    };

/// Why the action [entry] answers was refused, when [entry] is an
/// [outcomeOfProposedActionKind] logbook entry of [trajectory]'s whose
/// result is [Refused]; or [Refused] with why it is not one. An outcome that
/// ran is refused here, so what an action gave back, such as a file's
/// text, never leaves as a notice.
Future<Outcome<String>> _refusalWhy(
  Trajectory<Object?, Object?> trajectory,
  EntryId entry,
) async =>
    switch (await _bodyOf(trajectory, entry, outcomeOfProposedActionKind)) {
      Refused(:final why) => Refused(why),
      Ran(output: final recorded) => switch (readOutcomeOfProposedAction(
        recorded,
      )) {
        null => Refused('entry $entry names no proposal'),
        (proposed: _, :final result) => _whyRefused(result, entry),
      },
    };

Outcome<String> _whyRefused(Object? result, EntryId entry) {
  const notRefused = 'is not the outcome of a refused action';
  try {
    if (decodeOutcome<Never>(
          result,
          (_, field) => throw FormatException('$field: ran'),
        )
        case Refused(:final why)) {
      return Ran(why);
    }
  } on FormatException {
    return Refused('entry $entry $notRefused');
  }
  return Refused('entry $entry $notRefused');
}

/// Answers an event admitted to the trajectory's mission: with a model's
/// reply, with the notice that the trajectory is open, or with the notice
/// that an action was refused.
///
/// The airlock knows no chat: it asks [DecidesAndRecordsActions] to build
/// the requests that answer the event, which a module of the event's own
/// system makes from what is recorded, reaching nothing. Then it decides
/// them all at once, holding every exact request, so the decision is about
/// exactly what will be sent and can refuse any of it before a byte leaves.
/// Once allowed, the web driver sends them in order and stops at the first
/// that fails, without retrying.
///
/// A reply is drawn only from the outcome of a proposal to ask the model,
/// read from the trajectory's own chain: another program's result can read
/// as a reply, as a read's `{"kind":"text","text":…}` does.
final class AnswerEvent extends Program<Answer, List<WebResponse>> {
  const AnswerEvent();

  @override
  String get name => 'answer';

  /// The reach before its requests are built: what a refused build is
  /// decided and recorded as.
  @override
  Reach _reach(Answer answer) => AnswersEvent(answer, const []);

  @override
  Future<Outcome<Reach>> _reachOn<P>(
    Trajectory<Object?, P> trajectory,
    Answer input,
    P place,
  ) async {
    final airlock = trajectory._airlock;
    final built = switch (input) {
      ReplyToEvent(:final respondsTo, :final reply) =>
        switch (await _modelReplyOutcome(trajectory, reply)) {
          Refused(:final why) => Refused(why),
          Ran(output: final recorded) => switch (_modelReplyIn(recorded)) {
            null => Refused('entry $reply holds no model reply'),
            (FinishedReply() || CutOffReply()) && final modelReply =>
              await airlock.replyRequests(
                trajectory.id,
                place,
                respondsTo,
                modelReply,
              ),
          },
        },
      TrajectoryOpened() => await airlock.trajectoryOpenedRequests(
        trajectory.id,
        place,
      ),
      RefusalNoticeToEvent(:final respondsTo, :final refusal) =>
        switch (await _refusalWhy(trajectory, refusal)) {
          Refused(:final why) => Refused(why),
          Ran(output: final why) => await airlock.refusalNoticeRequests(
            trajectory.id,
            place,
            respondsTo,
            why,
          ),
        },
    };
    return switch (built) {
      Ran(output: final requests) => Ran(AnswersEvent(input, requests)),
      Refused(:final why) => Refused(why),
    };
  }

  @override
  _Wire<Answer, List<WebResponse>> get _wire => const _Wire(
    {'program': 'answer'},
    inputToJson: _answerToJson,
    inputFromJson: _answerFromJson,
    outputToJson: _webResponsesToJson,
    outputFromJson: _webResponsesFromJson,
  );

  @override
  Future<Outcome<List<WebResponse>>>? _on(
    Trajectory<Object?, Object?> trajectory,
    Answer answer,
    Reach reach,
    Report report,
  ) => switch ((trajectory._driver<CarriesOutWebRequests>(), reach)) {
    (null, _) => null,
    (final web?, AnswersEvent(:final requests)) => _send(web, requests),
    (_?, _) => throw StateError('an answer reaches only by AnswersEvent'),
  };

  static Future<Outcome<List<WebResponse>>> _send(
    CarriesOutWebRequests web,
    List<Request> requests,
  ) async {
    final responses = <WebResponse>[];
    for (final request in requests) {
      final sent = 'sent ${responses.length} of ${requests.length}';
      switch (await web.carryOutWebRequest(request)) {
        case Refused(:final why):
          return Refused('$sent: $why');
        case Ran(output: final response)
            when response.status < 200 || response.status > 299:
          return Refused(
            '$sent: ${response.status} ${response.refusedBecause ?? ''}'
                .trimRight(),
          );
        case Ran(output: final response):
          responses.add(response);
      }
    }
    return Ran(responses);
  }
}

/// Fetches from a site, through the sign-in it names, with a GET that sends
/// no body and no headers, and keeps the response's body as [WebFetch.keep]
/// asks: a document's bytes, or a listing's text.
///
/// Nothing is drawn from the record, since nothing is sent but the address.
/// The path is decided as written, so what the model chose for it reaches
/// only the origin the rules grant with that sign-in; a rule can bound it
/// further by prefix. Every byte kept is recorded in the outcome.
final class FetchFromWeb extends Program<WebFetch, WebResponse> {
  const FetchFromWeb();

  @override
  String get name => 'fetch';

  @override
  Reach _reach(WebFetch fetch) => FetchesFromWeb(fetch);

  @override
  _Wire<WebFetch, WebResponse> get _wire => const _Wire(
    {'program': 'fetch'},
    inputToJson: _webFetchToJson,
    inputFromJson: _webFetchFromJson,
    outputToJson: encodeWebResponse,
    outputFromJson: decodeWebResponse,
  );

  @override
  Future<Outcome<WebResponse>>? _on(
    Trajectory<Object?, Object?> trajectory,
    WebFetch fetch,
    Reach reach,
    Report report,
  ) => trajectory._driver<CarriesOutWebRequests>()?.carryOutWebRequest(
    Request(
      fetch.origin,
      path: fetch.path,
      signIn: fetch.signIn,
      keep: fetch.keep,
    ),
  );
}

/// A GET a tool asks for: where to, as whom, and what of the response's
/// body to keep. It has no body or headers to carry words.
final class WebFetch {
  const WebFetch(
    this.origin, {
    required this.keep,
    this.path = WebPath.root,
    this.signIn,
  });

  final Origin origin;
  final WebPath path;

  /// Who it goes as; null goes under no sign-in.
  final SignIn? signIn;
  final BodyToKeep keep;
}

/// Asks the model, through the model driver, as the [ModelCall]'s sign-in,
/// with the system prompt and request its recorded [ModelRequest] holds.
///
/// The one action the loop proposes for itself rather than drawing from an
/// intent in the model's reply: the loop holds no sign-in and has no
/// network, so this is its only way to reach the model
/// (https://github.com/enspyrco/intersyntactic/pull/1168). The airlock
/// allows it only as a sign-in the trajectory's rules let a model call go
/// out as.
///
/// Once allowed, the airlock reads the [ModelRequest] and each of its
/// pieces from this trajectory's own chain, joins each text, checks it
/// against its sha256, and hands the driver exactly those texts. Any piece
/// missing, on another chain, or not joining to its hash refuses the call
/// before the driver is reached. The reply streams as [ReplyArriving] in
/// [Underway], never recorded; the whole [ModelReply] is the outcome,
/// recorded once.
final class AskTheModel extends Program<ModelCall, ModelReply> {
  const AskTheModel();

  @override
  String get name => 'model';

  @override
  Reach _reach(ModelCall call) => CallsTheModel(call);

  @override
  _Wire<ModelCall, ModelReply> get _wire => const _Wire(
    {'program': 'model'},
    inputToJson: _modelCallToJson,
    inputFromJson: _modelCallFromJson,
    outputToJson: encodeModelReply,
    outputFromJson: decodeModelReply,
  );

  @override
  Future<Outcome<ModelReply>>? _on(
    Trajectory<Object?, Object?> trajectory,
    ModelCall call,
    Reach reach,
    Report report,
  ) => switch (trajectory._driver<AsksTheModel>()) {
    null => null,
    final driver => _ask(driver, trajectory, call, report),
  };

  static Future<Outcome<ModelReply>> _ask(
    AsksTheModel driver,
    Trajectory<Object?, Object?> trajectory,
    ModelCall call,
    Report report,
  ) async {
    final ModelRequest request;
    switch (await _bodyOf(trajectory, call.request, ModelRequest.kind)) {
      case Refused(:final why):
        return Refused(why);
      case Ran(output: final text):
        try {
          request = ModelRequest.fromJson(JsonObject.decode(text));
        } on FormatException catch (e) {
          return Refused('not a model request: ${e.message}');
        }
    }
    Future<Outcome<String>> joined(RecordedText recorded) async {
      final texts = <String>[];
      for (final piece in recorded.pieces) {
        switch (await _bodyOf(trajectory, piece, ModelRequestPiece.kind)) {
          case Refused(:final why):
            return Refused(why);
          case Ran(output: final text):
            try {
              texts.add(
                ModelRequestPiece.fromJson(JsonObject.decode(text)).text,
              );
            } on FormatException catch (e) {
              return Refused('not a model request piece: ${e.message}');
            }
        }
      }
      return recorded.join(texts);
    }

    final systemPrompt = await joined(request.systemPrompt);
    final asked = await joined(request.request);
    return switch ((systemPrompt, asked)) {
      (Refused(:final why), _) || (_, Refused(:final why)) => Refused(why),
      (Ran(output: final system), Ran(output: final text)) =>
        await driver.askTheModel(
          call.signIn,
          call.model,
          system,
          text,
          report: report,
        ),
    };
  }
}

/// A model call a loop proposes: as which of the person's model sign-ins,
/// to which model, and the [ModelRequest] entry, recorded on its
/// trajectory's chain before this, that holds exactly what is sent.
final class ModelCall {
  const ModelCall({
    required this.signIn,
    required this.model,
    required this.request,
  });

  final ModelSignInName signIn;
  final ModelName model;

  /// The [ModelRequest] entry.
  final EntryId request;
}

Object? _modelCallToJson(ModelCall call) => {
  'signIn': encodeModelSignInName(call.signIn),
  'model': encodeModelName(call.model),
  'request': call.request.hex,
};

ModelCall _modelCallFromJson(Object? input, String field) {
  final json = _object(field, input);
  return _at(field, () {
    _exactly(field, json, const {'signIn', 'model', 'request'});
    return ModelCall(
      signIn: decodeModelSignInName(json.raw('signIn'), '$field.signIn'),
      model: decodeModelName(json.raw('model'), '$field.model'),
      request:
          EntryId.parse(json.string('request')) ??
          (throw FormatException('$field.request: not an entry id')),
    );
  });
}

/// What an [AnswerEvent] answers with: a closed set.
sealed class Answer {
  const Answer();
}

/// The model's [reply], an outcome of a proposal to ask the model on this
/// trajectory, answering the event admitted by [respondsTo].
final class ReplyToEvent extends Answer {
  const ReplyToEvent({required this.respondsTo, required this.reply});

  /// The docking station's admission of the event: one that starts a turn
  /// on this trajectory, as the airlock checks.
  final EntryId respondsTo;
  final EntryId reply;
}

/// That the trajectory is open, answering the event that started it.
final class TrajectoryOpened extends Answer {
  const TrajectoryOpened();
}

/// That an action was refused, and why, answering the event admitted by
/// [respondsTo], so the person who sent it can decide what to do.
///
/// [refusal] is an outcome of a proposal on this trajectory, and its result
/// must be [Refused]: only the `why` the airlock recorded is told, never
/// what an action that ran gave back.
final class RefusalNoticeToEvent extends Answer {
  const RefusalNoticeToEvent({required this.respondsTo, required this.refusal});

  /// The docking station's admission of the event: one that starts a turn
  /// on this trajectory, as the airlock checks.
  final EntryId respondsTo;
  final EntryId refusal;
}

/// What an action would do to the world, typed, so the airlock can decide
/// and record it without knowing the action's types: one per [Program].
sealed class Reach {
  const Reach();
}

/// Reads the file at [path], as text or as its exact bytes. Either way it
/// reveals the same file, so a rule granting [path] grants both.
final class Reads extends Reach {
  const Reads(this.path, {this.as = ReadsAs.text});

  final RelativePath path;

  /// Which program reads it, so the record names the one that ran.
  final ReadsAs as;
}

/// How a [Reads] reads its file: [ReadFile] or [ReadFileBytes].
enum ReadsAs { text, bytes }

final class Writes extends Reach {
  const Writes(this.file);

  final FileText file;
}

final class Starts extends Reach {
  const Starts(this.program, this.args);

  final ProgramName program;
  final Args args;
}

/// Reaches the world: answers an event with [answer] by sending [requests],
/// exactly these, in order, each to its origin as its sign-in.
///
/// Holds every exact request, bodies among them, so the decision is about
/// what will be sent: the airlock grants each request's origin and sign-in
/// together, never the origin alone. Empty when the requests could not be
/// built, which is decided as a refusal.
final class AnswersEvent extends Reach {
  AnswersEvent(this.answer, List<Request> requests)
    : requests = List.unmodifiable(requests);

  final Answer answer;
  final List<Request> requests;
}

/// Reaches the world with an address alone: a GET goes to [origin], as
/// [signIn] or under none when null, and its response's body is kept as
/// [fetch] asks. Its own reach, so a grant to post somewhere is not a grant
/// to fetch from it, or the other way round.
///
/// A null sign-in means no sign-in, never any: a rule granting a site under
/// no sign-in must not match a fetch that has one, or a grant to read a
/// page anonymously would let a trajectory read there as a bot. A rule
/// grants the origin and the sign-in together, never the origin alone.
final class FetchesFromWeb extends Reach {
  const FetchesFromWeb(this.fetch);

  final WebFetch fetch;

  Origin get origin => fetch.origin;
  SignIn? get signIn => fetch.signIn;
  WebPath get path => fetch.path;
}

/// Reaches the model: [call] goes out as its sign-in, to its model, with the
/// texts its [ModelRequest] entry holds. A rule grants it by the sign-in,
/// one the trajectory's rules let a model call go out as.
final class CallsTheModel extends Reach {
  const CallsTheModel(this.call);

  final ModelCall call;

  ModelSignInName get signIn => call.signIn;
  ModelName get model => call.model;
}

/// One agent's own trajectory: the line its actions are proposed on, with
/// rules [R] that say what it may do, and places [P] that say where in a
/// turn each entry happened.
///
/// Its drivers are those it was given, acting for the path, each wherever
/// it runs. They are reached only by an [Action] proposed at its crux, so
/// every such action passes its airlock.
///
/// This is the airlock service's side of a trajectory, set up when the
/// record shows the docking station started the path (its rules, in
/// `admitted`) and loop_launcher handed it users (`assigned`). The airlock
/// starts nothing. Whoever holds the drivers already has the power to touch
/// the world, so setting up a side grants nothing new.
final class Trajectory<R, P> {
  /// The side of the trajectory named [id], on [drivers], decided and
  /// recorded by [airlock], under [rules], whose programs run as [suit].
  ///
  /// [id] is the hash of the record entry that started the path, which the
  /// docking station writes, so no two trajectories share one and nothing here
  /// mints one.
  Trajectory({
    required this.id,
    required Iterable<CarriesOutActions> drivers,
    required this._airlock,
    required this.rules,
    required this.suit,
  }) : _drivers = List.unmodifiable(drivers);

  /// Names this trajectory in every entry it records.
  final TrajectoryId id;
  final R rules;

  /// The OS user this path's programs run as: the airlock service gives the
  /// path a program driver that runs as it. One per path, kept for the
  /// path's life.
  final Suit suit;

  final DecidesAndRecordsActions<R, P> _airlock;
  final List<CarriesOutActions> _drivers;
  final _decisions = StreamController<AirlockDecisionOnAction<P>>.broadcast(
    sync: true,
  );
  final _results =
      StreamController<
        ({AirlockDecisionOnAction<P> decision, Outcome<Object?> result})
      >.broadcast(sync: true);
  final _underway = StreamController<Underway<P>>.broadcast(sync: true);
  bool _stopped = false;

  /// Refuses every action on this trajectory whose driver has not yet been
  /// reached. An action whose driver has been reached is not interrupted.
  /// Never undone.
  void stop() => _stopped = true;

  bool get stopped => _stopped;

  /// Each decision once the airlock has recorded it.
  Stream<AirlockDecisionOnAction<P>> get decisions => _decisions.stream;

  /// Each action's result, or why it was refused, once the airlock has
  /// recorded it, with the decision it follows.
  Stream<({AirlockDecisionOnAction<P> decision, Outcome<Object?> result})>
  get results => _results.stream;

  /// What drivers report while actions are underway: for a live view, and
  /// not recorded.
  Stream<Underway<P>> get underway => _underway.stream;

  D? _driver<D extends CarriesOutActions>() =>
      _drivers.whereType<D>().firstOrNull;

  Future<Outcome<O>> _consider<I, O>(
    Program<I, O> program,
    I input,
    P place, {
    required EntryId proposed,
  }) async {
    const stoppedByPerson = Deny('stopped', by: DecidedBy.person);
    final built = stopped
        ? Ran(program._reach(input))
        : await program._reachOn(this, input, place);
    final reach = switch (built) {
      Ran(output: final reach) => reach,
      Refused() => program._reach(input),
    };
    var decision = switch ((stopped, built)) {
      (true, _) => stoppedByPerson,
      (false, Refused(:final why)) => Deny(why, by: DecidedBy.rules),
      (false, Ran()) => await _airlock.decide(id, reach, rules),
    };
    if (stopped) decision = stoppedByPerson;
    final decided = AirlockDecisionOnAction(
      id,
      place,
      reach,
      decision,
      proposed: proposed,
    );
    await _airlock.recordDecision(decided);
    _decisions.add(decided);
    final Outcome<O> result = switch (decision) {
      Deny(:final why) => Refused(why),
      Allow() =>
        await program._on(
              this,
              input,
              reach,
              (progress) => _underway.add(Underway(id, place, reach, progress)),
            ) ??
            Refused('this machine cannot run ${program.name}'),
    };
    await _airlock.recordResult(
      decided,
      result,
      resultAsJson: encodeOutcome(result, program._wire.outputToJson),
    );
    _results.add((decision: decided, result: result));
    return result;
  }

  /// [proposal], the logbook entry [proposed] on this path's chain,
  /// considered at [place]: decided and recorded, and carried out by a
  /// driver if it is allowed. Its decision and its result both name
  /// [proposed]. The one way an action reaches this trajectory's drivers.
  ///
  /// Only for an entry on this path's own chain, which the logbook service
  /// takes only from this path's loop user. [place] is
  /// [ActionProposedByAgentLoop.place] read as a [P] by the airlock service,
  /// which knows [P].
  Future<void> consider(
    ActionProposedByAgentLoop proposal,
    P place, {
    required EntryId proposed,
  }) => proposal._work.on(this, place, proposed);
}

/// A trajectory's crux, at one place in a turn: its agent loop, the one
/// holder that extends the trajectory, proposing the next action there for
/// its airlock to decide, which records each entry at that place
/// (https://github.com/enspyrco/intersyntactic/pull/1168).
///
/// Made by [Crux.through] in the agent loop, a process of its own: an
/// action's program and input go into the logbook as an
/// [ActionProposedByAgentLoop], which the airlock service reads and
/// decides, and its continuation stays behind, since it is the tool's own
/// code. What comes after a tool's result takes a crux and never handles
/// the place. Two agents on one machine have
/// two cruxes; one step's two tool calls go through one trajectory's crux,
/// at two places.
sealed class Crux {
  const Crux();

  /// The crux for [turn] of the trajectory whose chain [link] writes to: it
  /// proposes each action at the turn's next step, from 0, so the model
  /// call, each action of a tool it asks for and the reply each get their
  /// own place, and a restarted loop gives each the same place again. Make
  /// one per turn and carry every action of the turn through it.
  factory Crux.through(
    ProposesActionsThroughTheRecord link, {
    required int turn,
  }) = _ThroughRecord;

  Future<Outcome<O>> _propose<I, O>(Program<I, O> program, I input);
}

/// Decides each action on a trajectory, and records it.
///
/// What intersyntactic's airlock implements. It guards the drivers it is
/// given, not the mission: an agent that joins a mission with its own
/// drivers is decided, or not, by its own.
abstract interface class DecidesAndRecordsActions<R, P> {
  /// Whether a driver may carry out an action of [trajectory]'s that would
  /// do [reach], under [rules].
  ///
  /// Given the reach, not the action, so the decision is about exactly what is
  /// recorded: for an [AnswersEvent], every request it sends, each to be
  /// granted by its origin and sign-in together. Given the trajectory,
  /// so the airlock can read what holds for it now from its chain, such as
  /// the bot leased to it, at the moment of deciding; the decision names
  /// each entry it read in [Decision.reliedOn].
  Future<Decision> decide(TrajectoryId trajectory, Reach reach, R rules);

  /// Keeps [decision] in the logbook. An action's driver is reached only
  /// once its decision is kept; an error thrown here ends the call.
  ///
  /// Kept means it survives the logbook service crashing or being killed,
  /// not a power cut: the logbook service answers before forcing the entry
  /// to disk, and a power cut can leave an entry with missing bytes, which
  /// its `check()` reports. So "no driver is reached without a recorded
  /// decision" holds across crashes
  /// (https://github.com/intersyntactic/logbook/pull/12).
  ///
  /// A decision starts a chain of its own in the logbook (previous `-`):
  /// the chain a proposal is on is its loop user's, which the airlock may not
  /// extend. Its body is [AirlockDecisionOnAction.toJson], under
  /// [AirlockDecisionOnAction.kind]. No two may be byte-identical, since the
  /// logbook service refuses a repeated chain start, so one made for a
  /// proposal names it.
  Future<void> recordDecision(AirlockDecisionOnAction<P> decision);

  /// Keeps in the logbook what the action [decision] was about came to:
  /// [result], what it ran to or why it was refused, which [resultAsJson]
  /// holds as its program's codec writes it. The action's continuation sees
  /// [result] only once it is kept; an error thrown here ends the call. Kept
  /// as [recordDecision] keeps.
  ///
  /// It extends [decision]'s chain, its previous the decision. Its body is
  /// [outcomeOfProposedActionToJson] of
  /// [AirlockDecisionOnAction.proposed] and [resultAsJson], under
  /// [outcomeOfProposedActionKind]: the one copy of what the action
  /// returned, which the loop that proposed it is waiting for.
  Future<void> recordResult(
    AirlockDecisionOnAction<P> decision,
    Outcome<Object?> result, {
    required Object? resultAsJson,
  });

  /// The kind and body of [entry], when it belongs to [trajectory]: the
  /// body as text, after its `<kind>\n<previous>\n` header. Or [Refused]
  /// with why not. Whoever reads it checks the kind it expects, since a
  /// loop may write a body of any shape under its own kinds.
  ///
  /// An entry belongs to a trajectory when it is on the trajectory's own
  /// chain, or when it is an [outcomeOfProposedActionKind] logbook entry the
  /// airlock kept for one of the trajectory's proposals: its `proposed` is
  /// on that chain. Only the airlock writes those, so a loop cannot make
  /// one. Any other entry is refused, never read: entry hashes are not
  /// secret, so without this a loop could name another trajectory's
  /// [ModelRequest], pieces or replies and have them sent as its own.
  /// [AskTheModel] reads its request and every piece through here, and
  /// [AnswerEvent] the model's reply.
  Future<Outcome<({String kind, String body})>> recordedOn(
    TrajectoryId trajectory,
    EntryId entry,
  );

  /// The requests that answer the event [respondsTo] admitted with [reply],
  /// proposed at [place], as the module of that event's system builds them,
  /// reaching nothing; or [Refused] with why there are none. Refused unless
  /// [respondsTo] is an admission of an event that starts a turn on
  /// [trajectory].
  ///
  /// [place] is where the loop said it proposed the answer, so a module may
  /// show it; the airlock checks nothing about it.
  ///
  /// The airlock picks the module and the sign-in the requests go as; the
  /// decision on them then grants each one's origin and sign-in.
  Future<Outcome<List<Request>>> replyRequests(
    TrajectoryId trajectory,
    P place,
    EntryId respondsTo,
    ModelReply reply,
  );

  /// The requests that tell the event that started [trajectory] that it is
  /// open, proposed at [place], built as [replyRequests] builds a reply's.
  Future<Outcome<List<Request>>> trajectoryOpenedRequests(
    TrajectoryId trajectory,
    P place,
  );

  /// The requests that tell the event [respondsTo] admitted that an action
  /// was refused, and [why], proposed at [place], built as [replyRequests]
  /// builds a reply's. [why] is a refusal's reason as the airlock recorded
  /// it, never anything an action gave back.
  Future<Outcome<List<Request>>> refusalNoticeRequests(
    TrajectoryId trajectory,
    P place,
    EntryId respondsTo,
    String why,
  );
}

/// What the airlock decided about one action, and [by] whom, so the record
/// tells "the rules let it through" from "the person said yes".
sealed class Decision {
  const Decision({required this.by, this.reliedOn = const []});

  final DecidedBy by;

  /// The logbook entries the airlock read to decide, beyond the rules: what
  /// held for the trajectory at that moment, such as the lease of the bot it
  /// may post as. Empty when the rules alone decided.
  final List<EntryId> reliedOn;
}

/// A driver may carry the action out.
final class Allow extends Decision {
  const Allow({required super.by, super.reliedOn});
}

/// No driver carries the action out, because [why]; its continuation is handed
/// [Refused] with that reason.
final class Deny extends Decision {
  const Deny(this.why, {required super.by, super.reliedOn});

  final String why;
}

/// What the airlock decided about an action that would do [reach], on the
/// trajectory named [trajectoryId], at [place] in a turn, before any driver
/// is reached. With no result recorded after it, the logbook shows the
/// action was cut short.
///
/// [place] is of type [P], which the agent loop supplies, since it knows
/// where in the turn it is, and the airlock records; nothing here computes
/// one.
final class AirlockDecisionOnAction<P> {
  const AirlockDecisionOnAction(
    this.trajectoryId,
    this.place,
    this.reach,
    this.decision, {
    required this.proposed,
  });

  /// The kind of the logbook entry the airlock keeps it as.
  static const kind = 'airlock-decision-on-action';

  /// [json] read back as [toJson] wrote it, its place read by
  /// [placeFromJson], null for one that is not a place. Each part is
  /// checked as its type's `parse` checks it; throws a [FormatException]
  /// naming the part.
  static AirlockDecisionOnAction<P> fromJson<P>(
    JsonObject json,
    P? Function(Object? json) placeFromJson, [
    String field = 'decided',
  ]) => _at(
    field,
    () => AirlockDecisionOnAction(
      TrajectoryId.parse(json.string('trajectory')) ??
          (throw FormatException('$field.trajectory: not a trajectory')),
      placeFromJson(json.raw('place')) ??
          (throw FormatException('$field.place: not a place')),
      _reachFromJson(json.object('reach'), '$field.reach'),
      _decisionFromJson(json.object('decision'), '$field.decision'),
      proposed: _proposedFromJson(json, field),
    ),
  );

  /// This decision as the logbook holds it, for every reach, its place
  /// written by [placeToJson]. The reach is the program and input that
  /// make it, as a proposal writes them.
  Object? toJson(Object? Function(P place) placeToJson) => {
    'trajectory': trajectoryId.hex,
    'place': placeToJson(place),
    'reach': _reachToJson(reach),
    'decision': _decisionToJson(decision),
    'proposed': proposed.hex,
  };

  final TrajectoryId trajectoryId;
  final P place;
  final Reach reach;
  final Decision decision;

  /// The [ActionProposedByAgentLoop] logbook entry that asked for the
  /// action.
  final EntryId proposed;
}

/// What a driver reported, [progress], while the action doing [reach] was
/// underway at [place] on the trajectory named [trajectoryId].
final class Underway<P> {
  const Underway(this.trajectoryId, this.place, this.reach, this.progress);

  final TrajectoryId trajectoryId;
  final P place;
  final Reach reach;
  final Progress progress;
}
