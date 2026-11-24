# Changelog

## 0.18.1

- A driver that throws no longer leaves a decision with no result, which
  reads the same as the airlock crashing. Its result is written as
  `StoppedPartway` with `done` null, since it may have reached the world
  first, and the throw still ends the call.

## 0.18.0

Breaking, through is_effects ^0.15.0, which splits `Refused` by whether
the world changed: `NothingRan(why)` or `StoppedPartway(why, done)`.

- `runOrRefusal` is now `runOrFail`. A tool fails unless the program ran to
  the end; one that stopped partway says so in its failure.
- A denied action, one this machine has no driver for, and a model request
  whose entries are missing or malformed are `NothingRan`.
- `MakeWebRequests` is `NothingRan` only when its first request never went
  out. After that it is `StoppedPartway`, its `done` the response to each
  request that finished, a non-2xx one included. A request that went out
  with no response is named in `why`, never in `done`.
- A rejected proposal's result is written as `nothingRan`.
- `Allow.by` is `DecidedBy?`, required but nullable: null means no rule
  governs the reach, such as a read or write bounded only by the file
  driver's root, so the logbook no longer says "rules" when none exist. It
  is left out of the decision entry when null. `Deny.by` stays required,
  and a denial read back without one is refused. `by` moved from
  `Decision` onto `Allow` and `Deny`.
- `ModelRequest` is now `ModelRequestFromPieces`, so it no longer shares a
  name with is_model_vocabulary's `ModelRequest`, which is what the joined
  request text holds. Its logbook kind stays `model-request`.

## 0.17.0

Breaking, through is_effects ^0.14.0, which splits `Request` into
`ProposedRequest` and `GrantedRequest`.

- `MakeWebRequests` takes `ProposedRequest`s, read and written with
  `decodeProposedRequest` and `encodeProposedRequest`, which refuse a
  `grantedPathPrefix`.
- `Allow` names `grantedPathPrefixes`, required: one per request of a
  `MakesWebRequests`, in order, and one for a `FetchesFromWeb`.
  `Allow.withNoPaths` is for every other reach.
- A web action reaches its driver only as `GrantedRequest`s built under
  those prefixes, so a redirect on the same site stays where the rule
  granted. Allowed with the wrong number of prefixes, or under one that
  doesn't cover its path, it is refused and nothing is sent.
- The decision entry writes `grantedPathPrefixes` and leaves it out when
  empty, so a decision that grants no path keeps its bytes.

## 0.16.0

Breaking, through is_effects ^0.13.0, whose types this API names.

- `Executable.parse` refuses a name with `/`, a NUL, or `.` or `..` alone,
  since a program is named, never located. `WebPath.parse` refuses a path
  the URI parser would rewrite. A proposal carrying either is rejected.
- A dependent can now take is_effects 0.13 alongside this package, for
  its `PathPrefix`, `AddressPrefix` and `Request.grantedPathPrefix`.
- A proposal's request that names a `grantedPathPrefix` is rejected: only
  a grant gives one, never the tool.

## 0.15.0

Breaking. The airlock knows no module: the tool on the other side of a
proposal builds what it sends, and the airlock decides where it may go.

- `MakeWebRequests` (`Program.makeWebRequests`, proposed as
  `make-web-requests`) replaces `AnswerEvent`. Its input is the exact
  `Request`s the tool built, in is_effects's codec; its reach is
  `MakesWebRequests(requests)`. The airlock grants each request's
  origin, sign-in and path together, all or none, so the path prefix a
  rule grants is what keeps a reply in its own conversation. It checks
  where a body goes, never what it says. At the boundary, a GET (a fetch),
  any header but `content-type`, and an empty list are refused. Sent in
  order; the first failure stops the rest.
- Removed: `AnswerEvent`, `Answer`, `ReplyToEvent`, `TrajectoryOpened`,
  `RefusalNoticeToEvent`, `AnswersEvent`, and
  `DecidesAndRecordsActions.replyRequests`, `trajectoryOpenedRequests` and
  `refusalNoticeRequests`. An airlock no longer picks a module or builds
  a request, so it never reads what strangers sent. A tool tells a person
  why an action was refused by building that message itself.
- With nothing left to build before deciding, a reach is always what its
  input says; the "refused build is a Deny" path is gone.
- The chain of entries is the logbook, never "the record", and the airlock
  writes to it. Renamed, with no old names kept:
  `ProposesActionsThroughTheRecord` → `ProposesActionsThroughTheLogbook`;
  `DecidesAndRecordsActions` → `DecidesActionsAndWritesToTheLogbook`, with
  `recordDecision` → `writeDecision`, `recordResult` → `writeResult` and
  `recordedOn` → `entryOn`; `RecordedText` → `TextFromPieces`. The docs
  and README say "the logbook" and "entry" throughout. Entry kinds are
  unchanged.
- `PlaceInTrajectory` is sealed: `ProposedForTheModelCall(turn)`, written
  `[turn, "model-call"]`; `ProposedForAnIntent(turn, intent, action)`,
  written `[turn, intent, action]`; or `ProposedForTheReply(turn, action)`,
  written `[turn, "reply", action]`, in that order within a turn. A place is
  fixed by where an action sits in the model's reply, never by the order
  things ran in, so two tools running at once can no longer swap places
  across a restart. 0.14's `[turn, step]` is not a place. `Crux.through` is
  gone: `Crux.forTheModelCall(link, turn:)` carries exactly one action, and
  `Crux.forIntent(link, turn:, intent:)` and `Crux.forTheReply(link,
  turn:)` number theirs. A reply has several actions because the message
  is built by a program on the box (such as a `teams-message` app, run by
  name through the program driver) and then sent exactly as built, so the
  airlock never holds a module's code.
- README: the example and the trajectory section no longer show
  `Trajectory.at`, which 0.14.0 removed.

## 0.14.0

Breaking. An action reaches a trajectory's drivers only through the
record: the airlock service has no crux of its own.

- `Trajectory.at(place)` is removed. It proposed actions inside the
  airlock service's own process, with no `ActionProposedByAgentLoop`
  logbook entry for the decision to answer. No production code called it.
  `Crux.through(link, turn:)` is the only crux, and the airlock service
  decides only what `Trajectory.consider` hands it from the record.
- `AirlockDecisionOnAction.proposed` is a required `EntryId`, never null:
  every decision names the proposal it answers. `fromJson` refuses a
  decision without one, as 0.13 wrote for an action proposed in-process.
- `DecidesAndRecordsActions.replyRequests(trajectory, place, respondsTo,
  reply)` and `trajectoryOpenedRequests(trajectory, place)` take the place
  the answer was proposed at, so the module that builds its requests can
  show it (a Teams card prints "turn N"). It is the loop's claim; the
  airlock checks nothing about it.
- `RefusalNoticeToEvent(respondsTo:, refusal:)` (proposed as
  `{"answer": "refusal-notice", …}`) answers an event with the notice that
  an action was refused, and why, so the person who sent it decides what to
  do. `refusal` names an outcome of a proposal on this trajectory whose
  result is `Refused`; an outcome that ran is refused, so what an action
  gave back never leaves as a notice. The module builds its requests
  through the new `DecidesAndRecordsActions.refusalNoticeRequests(
  trajectory, place, respondsTo, why)`, given only the recorded reason.
- `DecidesAndRecordsActions.recordResult` always keeps an
  `outcome-of-proposed-action` logbook entry; there is no decision without
  a proposal to answer.
- Tests that drove a trajectory with `.at` drive it through
  `Crux.through` with an in-memory `ProposesActionsThroughTheRecord`
  instead, which calls `Trajectory.consider` for each proposal it is
  written.

## 0.13.1

- `ActionProposedByAgentLoop.reach`: what a proposal read back proposes to
  do, as far as its input alone says, so a loop can tell its own
  `AnswersEvent(answer: TrajectoryOpened())` from a reply in its history.
  An `AnswersEvent`'s requests are empty here; they are built when it is
  decided.

## 0.13.0

Breaking, for the agent loop and the airlock alike. The airlock knows no
chat: nothing here builds or checks a Teams body any more.

- `AnswerEvent` (`Program.answerEvent`, proposed as `answer`) replaces
  `MakeWebRequest`. It answers an event admitted to the mission with an
  `Answer`: `ReplyToEvent(respondsTo:, reply:)` or `TrajectoryOpened()`.
  The airlock builds the requests first, reaching nothing, then decides
  one reach holding every exact request, `AnswersEvent(answer, requests)`,
  and sends them in order, stopping at the first that fails:
  `Refused('sent k of n: …')`. A build that cannot be made is decided as
  `Deny(why)` with no requests.
- `DecidesAndRecordsActions` gains `replyRequests(trajectory, respondsTo,
  reply)` and `trajectoryOpenedRequests(trajectory)`: the airlock checks
  the admission, picks the module and the sign-in, and the module builds
  the requests (is_effects's `BuildsRequestsAnsweringEvents`).
- Removed: `MakeWebRequest`, `WebRequest`, `MakesWebRequest`,
  `Projection` (with `teamsMessageFromModelReply` and
  `trajectoryOpenCard`), `trajectoryOpenCardBody`, and
  `AirlockDecisionOnWebRequest` with its entry kind. Every decision is an
  `AirlockDecisionOnAction`; an `AnswersEvent`'s requests are written in it
  with is_effects's `encodeRequest`, exact bodies included.
- `FetchFromWeb` (`Program.fetch`, proposed as `fetch`): a GET with no body
  or headers, taking a `WebFetch` (origin, path, sign-in, `keep`), and
  giving the `WebResponse` with the body it kept. Its path is decided as
  written. Its own reach, `FetchesFromWeb`, so a grant to post to a site
  is not a grant to fetch from it.
- `ReadFileBytes` (`Program.readBytes`, proposed as `read-bytes`): a
  file's exact bytes. It shares the `Reads` reach, which now carries
  `as: ReadsAs.text | bytes`, so a rule granting a path grants both reads
  and the record says which ran.
- `Program._reachOn`: a program may work out its reach before it is
  decided, reaching no driver. Every program but `AnswerEvent` uses its
  input alone.

## 0.12.1

- Takes is_effects `^0.11.0`. Its one break is
  `ReadsAndWritesFiles.readBytes`, which matters only to a file driver that
  implements it; nothing in this package's API changes.

## 0.12.0

Breaking, for the agent loop and the airlock alike.

- `PlaceInTrajectory(turn, step)`: where in its trajectory a loop proposed
  an action, written `[turn, step]`, ordered by turn then step.
  `ActionProposedByAgentLoop.place` is one, and a proposal without one is
  `Rejected('not a place')`.
- `Crux.through(link, turn:)` replaces `Crux.through(link, place:)`. Make
  one per turn: it proposes each action at the turn's next step from 0, so
  a tool that takes several actions gives each its own place, and a
  restarted loop gives each the same place again.
- `ProposesActionsThroughTheRecord` is `writeProposal(body)`, giving the id
  the logbook gave the entry, and `outcomeNaming(id)`, giving the outcome
  entry's body. `propose` is gone. This package joins the two and refuses
  an outcome that names another proposal, so a loop never works out an id.
- `DecidesAndRecordsActions.decide(trajectory, reach, rules)`: the airlock
  is told which trajectory acts, so it can read what holds for it now,
  such as the bot leased to it.
- `Decision.reliedOn`: the logbook entries the airlock read to decide,
  beyond the rules. `AirlockDecisionOnWebRequest` writes them as
  `decision.reliedOn` only when there are any, so a decision kept before
  reads back to the same bytes.
- `AirlockDecisionOnAction.toJson(placeToJson)` and
  `AirlockDecisionOnAction.fromJson(json, placeFromJson)`: a decision of
  every reach, as the logbook holds it under `airlock-decision-on-action`.
  The reach is written as the program and input that make it, exactly as a
  proposal writes them, so the airlock can rebuild from history which
  places it decided and which decisions have no result after them, for
  every kind of action. A web request's decision keeps its own entry,
  byte for byte.

## 0.11.1

- A `teams-message-from-model-reply` request is sent only when the
  outcome it is drawn from answers a proposal that asked the model. A
  read's result, `{"kind":"text","text":…}`, also reads as a model reply,
  so a loop could have sent a file's contents to Teams. The airlock reads
  the proposal from the trajectory's own chain: one more logbook read per
  send.

## 0.11.0

Breaking. Takes is_effects `^0.9.0`, reads JSON with checked_json, and adds
a trajectory open card.

- is_effects 0.9.0: `WebRequestOutcome` is `WebResponse`, and a
  `ModelReply` is `FinishedReply` or `CutOffReply`, with token usage.
- A cut-off reply reaches Teams with a blank line and `_(reply cut off)_`
  after its text, so it never reads as the whole answer.
- `Projection.trajectoryOpenCard`: the card that shows a trajectory is
  open, with one Close action (verb `close`), exactly
  `trajectoryOpenCardBody`. Its request's `drawnFrom` is the trajectory's
  own id, and the airlock reads nothing to check it.
- JSON is read with checked_json's `JsonObject`, checked once where it is
  decoded.
- Every `fromJson` takes a `JsonObject`: `AirlockDecisionOnWebRequest`,
  `ModelRequest`, `ModelRequestPiece`, `RecordedText` and `WaitingToStart`.
  Decode a logbook entry's body with `JsonObject.decode(body)`, which throws
  a `FormatException` for anything but an object. `JsonObject` and
  `JsonFieldException` are exported.
- `ActionProposedByAgentLoop.read` and `readOutcomeOfProposedAction` take
  the logbook entry's body text, not decoded JSON, and still never throw:
  a body that is not a JSON object is `Rejected('not a proposal')` or
  null.
- Error messages are unchanged: a field of the wrong shape is still named
  by its dotted path, as `decided.request.body: not a string`.
- `Projection.teamsMessageFromModelReply` reads the reply with is_effects's
  `decodeModelReply`, not a pattern of its own, so a reply that gains a
  field there (token usage, coming) is still drawn from. Same bytes out.

## 0.10.2

- `ActionProposedByAgentLoop.program`: the program a proposal names, as a
  type, so a reader of the record tells a model call from a web request
  with `ActionProposedByAgentLoop(program: AskTheModel())` rather than
  comparing the wire's `program` string.

## 0.10.1

- Takes the newest is_effects and is_shapes, `^0.8.0` and `^0.6.0`, not a
  range reaching back to 0.7.0 and 0.5.0. No code changes: nothing here
  uses `ProgramMessage`, the one thing is_effects 0.8.0 broke.

## 0.10.0

Breaking.

- A proposal's answer is the logbook kind `outcome-of-proposed-action`
  (was `result-of-action-or-why-refused`): `outcomeOfProposedActionKind`,
  written by `outcomeOfProposedActionToJson` and `proposalRejectedToJson`,
  read by `readOutcomeOfProposedAction`. The body is unchanged,
  `{"proposed": <hex>, "result": <outcome>}`, and reads back as the record
  `(proposed:, result:)`, not a type.
- Takes is_effects `>=0.7.0 <0.9.0` and is_shapes `>=0.5.0 <0.7.0`, not
  `^0.7.0` and `^0.5.0`, so it resolves alongside is_effects 0.8.0 and
  is_shapes 0.6.0 (which drops `RendererId`, used nowhere here). Built and
  tested at both ends of each range.

## 0.9.0

Breaking. Every name says what the thing is, and the airlock's two writes
are two methods.

- `Proposal` is `ActionProposedByAgentLoop`, kind
  `action-proposed-by-agent-loop` (was `proposed`). Same body.
- `Decided<P>` is `AirlockDecisionOnAction<P>`, with
  `AirlockDecisionOnAction.kind` = `airlock-decision-on-action` for the
  logbook entry the airlock keeps it as. It no longer extends anything.
- `DecidedWebRequest` is `AirlockDecisionOnWebRequest`, kind
  `airlock-decision-on-web-request` (was `web-request-decided`). It
  carries the request's exact body, no renderer, and now `proposed`, the
  proposal it answers, so no two decisions start byte-identical chains:
  the logbook service refuses a repeated chain start once it names entries
  by the hash of their text.
- The renderer is gone: `Renderer`, `RendererName`, `Rendered` (kind
  `rendered`), `DecidesAndRecordsActions.renderer` and `.rendered`, and
  the `RendererId` export. A `WebRequest` carries its exact `body`, the
  `Projection` it is drawn by, and `drawnFrom`, the recorded entry it is
  drawn from, in place of a renderer's name and entries. Once allowed, the
  airlock reads `drawnFrom` through `recordedOn`, draws the body by the
  projection, and reaches the web driver only when it is byte-identical
  to `body`. One projection: `teamsMessageFromModelReply`
  (`teams-message-from-model-reply`), a Teams message whose text is a
  model's reply. A web request's chain is its decision, then its result.
- `DecidesAndRecordsActions.recordedOn` gives `({kind, body})`, the body
  after its header, of an entry that belongs to the trajectory: on its own
  chain, or a `result-of-action-or-why-refused` the airlock kept for one of
  its proposals. Each reader checks the kind it expects, since a loop may
  write a body of any shape under its own kinds: a web request draws only
  from a `result-of-action-or-why-refused`, and a model call reads only a
  `model-request` and its `model-request-piece`s.
- `Entry<P>`, `Returned<P>` and `ReturnedProposal` are gone.
  `DecidesAndRecordsActions.record(entry)` is
  `recordDecision(decision)` and `recordResult(decision, result,
  resultAsJson:)`; a result is handed the decision it follows, so a web
  request's result names its decision as its previous without a lookup.
  `Trajectory.entries` is `decisions` and `results`, the latter
  `({decision, result})`.
- A proposal's answer is the logbook kind
  `result-of-action-or-why-refused` (was `returned`), body
  `{"proposed": <hex>, "result": <outcome>}` (the `outcome` key is now
  `result`), written by `resultOfActionOrWhyRefusedToJson` and
  `proposalRejectedToJson` and read by `readResultOfActionOrWhyRefused`,
  which gives `(proposed:, result:)` or null when the body is not one.
- Docs: the journal is the logbook (is_logbook, run on the box by the
  logbook service), and links and `Logbook.builtDefine` point at
  https://github.com/intersyntactic/logbook. A web request's chain is
  written out in full: the decision starts it, since the proposal's chain
  is its loop user's alone. A model call goes out as a sign-in the rules
  let it go out as; the loop holds none.

## 0.8.0

The model call is an action (Nick, 17 Nov 20:12: "shit so the model call
should really go through the airlock hey?", 20:16: "we do it tonight";
https://github.com/enspyrco/intersyntactic/pull/1168, replacing the
12 Nov ruling that the model is the agent planning). Breaking.

- `AskTheModel` (`Program.askTheModel`, proposed as `model`): a
  `ModelCall` of a `ModelSignInName`, a `ModelName` and the `ModelRequest`
  entry, answered by a `ModelReply`. Its reach is `CallsTheModel`. The one
  action the loop proposes for itself.
- `ModelRequest` (kind `model-request`) and `ModelRequestPiece` (kind
  `model-request-piece`): what a step sends, recorded before it is sent,
  its `systemPrompt` and `request` each a `RecordedText` of piece entries
  and a sha256, with `join`.
- `DecidesAndRecordsActions.recordedOn(trajectory, entry)`, new and
  required: an entry's content, only from that trajectory's own chain.
  `AskTheModel` reads its request and pieces through it, joins and checks
  each text, and hands is_effects's `AsksTheModel` driver exactly those.
- The reply streams as is_effects's `ReplyArriving` in `underway`, never
  recorded. Depends on is_effects ^0.7.0.

## 0.7.1

- Takes is_effects `>=0.6.0 <0.8.0`, not `^0.6.0`. is_flight_rules 0.1.0
  needs is_effects 0.7.0, and below 1.0 `^0.6.0` excludes it, so nothing
  could depend on both (loop-launcher-5b found it). is_effects 0.7.0 only
  adds to what this package uses: its new `Progress` case,
  `ReplyArriving`, is never switched over here. Built and tested against
  0.7.0.

## 0.7.0

Breaking. "Send" is retired (Nick, 17 Nov 13:31: no tiny words for
complex things), and an interface is named for what it can do, so
`implements` reads as a true sentence (Nick, 17 Nov 13:55: "\"What it can
do\", yes naming rule";
https://github.com/enspyrco/intersyntactic/pull/1164). A journey is now a
mission, and a journey path a trajectory (Nick, 17 Nov 19:07 and 19:09;
19:15: "Rename tonight, before any real write").

- `JourneyPath<R, P>` is `Trajectory<R, P>`, and `JourneyPathId` is
  is_shapes 0.5.0's `TrajectoryId` (it hashes as before). Every
  `journeyPath` field is `trajectory`, on the wire too: `WaitingToStart`
  is `{"trajectory": <hex>}`, and `DecidedWebRequest` writes `trajectory`.
  Depends on is_shapes ^0.5.0.
- `Apex` is `Crux` (Nick, 17 Nov 20:17: "CRUX! That's what I was thinking
  of when I said 'apex'"): a trajectory's crux is its agent loop, the one
  holder that extends it (https://github.com/enspyrco/intersyntactic/pull/1168).
  `Trajectory.at(place)` and `Crux.through(link, place:)` give it at one
  place; one step's tool calls go through the one crux at their places.
- `Airlock<R, P>` is `DecidesAndRecordsActions<R, P>`, and `RecordLink` is
  `ProposesActionsThroughTheRecord`. The airlock and its drivers are still
  called that: only the interfaces are renamed, since a noun is kept for
  a thing that exists. No alias is kept.
- Depends on is_effects ^0.6.0, whose 0.4.0 renamed its driver interfaces
  the same way and whose 0.5.0 renamed one again: `Driver` is
  `CarriesOutActions`, `FileDriver` is `ReadsAndWritesFiles`,
  `ProgramDriver` is `RunsPrograms` (its `start` is `runProgram`), and
  `WebDriver` is `CarriesOutWebRequests`. So `JourneyPath(drivers:)`
  takes `Iterable<CarriesOutActions>`. 0.6.0 renamed codecs this package
  does not call.

- `Send` is `WebRequest` (Nick, 16 Nov 18:46), `WebSend` is
  `MakeWebRequest`, and `Sends` is `MakesWebRequest`, whose field `send` is
  `request`. These read with the other programs and reaches (`ReadFile`,
  `Reads`).
- `DecidedSend` is `DecidedWebRequest`, kind `web-request-decided`, with
  the JSON key `request` in place of `send`. No entry was ever written with
  the old kind. `send_entries.dart` is `web_request_entries.dart`.
- is_effects 0.3.0 made the same change:
  `WebDriver.send` is `carryOutWebRequest`, and `Sent` is
  `WebRequestOutcome`, so `MakeWebRequest` gives a `WebRequestOutcome`.
  "Renderer" is not decided and is unchanged.

## 0.6.0

Breaking.

- `Run` is now `Action`, and the library's file `run.dart` is `action.dart`
  (Nick, 17 Nov: "we retired 'run' did we not?", then "So it goes Turn ->
  Step -> Tool Call -> Action" and "'The airlock sits between intents and
  action' just sounds so good"). An action is one round trip to the world,
  which the airlock decides, with exactly one `Outcome`. The verb stays:
  `Program.run(input, then:)` and `runOrRefusal` still run a program, and
  a loop still runs as its user.
- `Held` (kind `held`) is now `WaitingToStart` (kind `waiting-to-start`),
  named for what happens: the path has started and its work has not
  begun (Nick, 17 Nov: "waiting-to-start"; a traveller does not know what
  a loop is or what held means). `Held` shipped in 0.5.0 but was missing
  from its changelog. No entry was ever written with the old kind.
- Docs: "follow" is retired (https://github.com/enspyrco/intersyntactic/pull/1155).
  A reader subscribes to the record, an entry names its previous, and a
  tool's result is run through at an apex. No API changes.

## 0.5.0

Breaking. The agent loop and the airlock in separate processes (RULINGS,
"No server"), and the renderer following the journal instead of being run
by the airlock
(https://github.com/enspyrco/intersyntactic/issues/1147#issuecomment-6905923566).

- The airlock never talks to a renderer. `Renderers` is gone, and with it
  `JourneyPath.start(renderers:)`. `Airlock` gains `renderer(name)`, which
  resolves a name for the `Decided` entry as `Renderers.find` did, and
  `rendered(decided)`: the body the renderer recorded after that `Decided`,
  which the airlock follows the journal to, or why there is none. It is
  called only once `Decided` is kept, and what it gives is what is sent,
  so the exact bytes sent are in the record. The check that a renderer was
  built from the source its id names moves to the entry it records.
- A proposal is an entry in the record, and the airlock has no door of its
  own (Nick, 16 Nov, https://github.com/enspyrco/intersyntactic/pull/1156).
  `Apex.through(link, place:)`: an apex in the agent loop that proposes each
  run's program and input over a `RecordLink` as a `Proposal` (kind
  `proposed`), an effect not yet decided, on the loop's journey path's
  chain, and keeps the continuation. `JourneyPath.at` is unchanged, and
  `Apex` is now sealed, with the two kinds, so a tool does not change.
- A `Proposal` names no journey path: the journal takes a path's chain only
  from its loop user, so the airlock takes the path from the chain.
  `Proposal.read(json)` gives a `Proposal` or `Rejected`;
  `JourneyPath.consider(proposal, place, proposed:)` decides and records
  it, and `Decided` and `Returned` gain `proposed`, the entry that asked.
- What an effect returns is in the record, once (Nick, 16 Nov,
  https://github.com/enspyrco/intersyntactic/pull/1157): `ReturnedProposal`
  (kind `returned`) holds what came back in full, by the program's codec,
  or the refusal, naming the `proposed` entry; loop_launcher hands it to
  the path's loop. `ReturnedProposal.refused` answers a `Rejected` entry.
  `Returned`'s constructor is private, since only a journey path knows the
  program's codec.
- `JourneyPath.start(...)` is now the unnamed `JourneyPath(...)`, taking
  the same arguments: it is the airlock service's side of a journey path,
  and the airlock starts nothing; the docking station starts journey paths
  (Nick, 16 Nov).
- `LoopUser` (`loop-<n>`) and `Suit` (`suit-<n>`), moved here from
  loop_launcher so both services read one type: the OS users loop_launcher
  hands each path from pools made ahead of time and records in the path's
  `assigned` entry. A path's loop runs as its loop user and its programs as
  its suit, one per path, contained or open (Nick, 16 Nov: "suit";
  https://github.com/enspyrco/intersyntactic/pull/1158). `JourneyPath`
  takes `suit`.
- loop_launcher records itself (Nick, 16 Nov, 19:22), so the airlock
  service learns each path from the record: the path-start message
  (`PathStarted`, `Ready`), the path token and `JourneyPath.reissue`,
  briefly on main, never shipped.
- `Post` is now `Send`, and `WebPost` is `WebSend`; `Sends` holds `send`
  where it held `post` (Nick, 16 Nov: "post" is ambiguous, beside the HTTP
  method `Method.post` and a chat's posts). So the family reads `Send`,
  `Sends`, and is_effects's `Sent`.
- Programs, inputs and outputs travel by is_effects's codecs; a `Send` by
  its own, built on them.
- One send's chain in the journal has wire forms: `DecidedSend` (kind
  `send-decided`: journey path, place, the whole `Send`, the exact
  `Renderer` or none, and the decision), which a renderer follows the
  journal for and reads, and `Rendered` (kind `rendered`: the `EntryId` of
  the `DecidedSend` it follows, the renderer's source id as it reports it,
  and the body or why there is none), which the renderer writes and the
  airlock reads. `Returned` follows `Rendered`, or follows the
  `DecidedSend` directly when the renderer did not answer in time. Only a
  send's entries have a wire form: other runs' entries still record what a
  run reached and why, never a file's text or a program's output.
- Depends on `is_effects` ^0.2.1, for its codecs.

## 0.4.0

Breaking. The post design decided in
https://github.com/enspyrco/intersyntactic/issues/1147: everything a post
says is drawn from recorded journal entries, by a renderer the record names
exactly.

- `Program.web` is a `WebPost`, a `Program<Post, Sent>`, in place of
  `WebRequest`, a `Program<Request, Sent>`. A `Post` has an origin, method,
  `WebPath`, sign-in, headers (checked by is_effects's `validatedHeaders`),
  a `RendererName` and the `EntryId`s of the recorded entries its words are
  drawn from. It has no body, so a tool cannot put words in.
- `Renderers`, which the service that starts journey paths implements and
  passes to `JourneyPath.start(renderers:)`: `find` resolves a
  `RendererName` to an exact `Renderer` (its `RendererId` and the `ObjectId`
  of the executable run); `render` reads and checks each entry and runs the
  renderer, giving the body or why there is none. A render is refused
  when the executable reports being built from source other than the
  renderer's id, which rules out a stale or mis-built executable, not one
  built to lie.
- A post's renderer is resolved before the decision, and `Sends` holds the
  whole `Post` and that `Renderer`, so the `Decided` entry records which
  code will write the words. A name that resolves to nothing, or a journey
  path with no `Renderers`, is denied before the rules are asked. The body
  is drawn only once `Decided` is kept, and a render that is refused (an
  entry the journal does not hold, say) refuses the post with nothing sent.
- `Airlock.decide` takes the `Reach`, not the `Run`, and `Decided`,
  `Returned` and `Underway` hold the `reach` in place of the `run`. The
  public `Run.reach` is gone: a post's reach needs its renderer resolved.
- `Airlock.record`'s doc says what kept means: it survives the journal
  crashing or being killed, not a power cut
  (https://github.com/intersyntactic/journal/pull/12).
- Re-exports `EntryId` and `RendererId` from `is_shapes`, and `ObjectId`
  from `is_content_id`.
- Depends on `is_effects` ^0.2.0, `is_shapes` ^0.4.4 and `is_content_id`
  ^0.2.0.

## 0.3.1

- `DecidedBy` is `is_shapes`'s, re-exported, so the airlock and the docking
  port record who decided with one type. The values and their order are
  unchanged (`rules`, `person`), and so is `Decision.by`. Code written
  against 0.3.0 compiles as it was; code importing both packages now sees
  one `DecidedBy`, not two that clash.
- Depends on `is_shapes` ^0.4.3.

## 0.3.0

Breaking.

- `JourneyPathId` is `is_shapes`'s: a journey path is named by the hash of
  the record entry that started it, which whoever starts it writes
  (`JourneyPathId.of(entryBytes)`), the way a `JourneyId` names a journey.
  This package's own `JourneyPathId`, whose `parse` took any non-blank
  string, is gone, and it re-exports `is_shapes`'s.
- Narrowing is removed: `JourneyPath.narrowed`, the `Narrowed` entry and
  `Airlock.narrows`. A `Narrowed` entry went into the parent's record and
  named the child, so the child's id had to exist before the entry that
  would name it, and could not be its hash. Nothing narrowed. With it go
  stopping a child when its parent stops, and entries and progress
  reaching a parent's streams.
- `Entry<R, P>` is `Entry<P>` again, with `Decided<P>` and `Returned<P>`:
  only `Narrowed` held rules.
- Depends on `is_shapes` as well as `is_effects`.

## 0.2.0

Breaking.

Added to this entry with 0.3.0: the 0.2.0 release also made these changes,
which its own changelog left out.

- Every entry is at a place `P` in a turn, which the agent loop supplies:
  `JourneyPath<R, P>`, `Airlock<R, P>`, and a `place` on each entry and on
  `Underway`.
- `journeyPath.at(place)` gives an `Apex`, and a run is carried out with
  `run.next(apex)`.
- `Entry<R, P>`, so a switch over the kinds of entry is exhaustive.
- `WebRequest` (`Program.web`) sends an `is_effects` `Request` through a
  `WebDriver`. Its reach is `Sends(origin, signIn)`, which a rule grants
  together and which never holds the body; a null sign-in means none.
- `Result.map`, which gives a result's answer to a function and carries out
  nothing.
- `PathInRepo` is `is_effects`'s `RelativePath`.

The changes it did list:

- The vocabulary of effects and the driver interfaces move to `is_effects`:
  `PathInRepo`, `FileText`, `Args`, `ReadResult`, `Wrote`, `ExecResult`,
  `Outcome`, and `FileDriver` and `ProgramDriver`. A driver depends on
  `is_effects` alone and sees no run, journey path or decision. This package
  depends on `is_effects` and nothing else of ours.
- `Tool`, `answeredBy`, `Reply` and `ExecResult.output` move to `is_tool`
  (as `Answer`, `answeredBy`, `Reply` and `execResultOutput`), so a
  consumer can take this up before its tools move to `is_tools_api` 0.2.
- `Executable` wraps an `is_effects` `ProgramName`, compares by it, and has
  `Executable.parse`; `Starts.program` is the `ProgramName`.
- `Allow` and `Deny` take `by: DecidedBy.rules` or `DecidedBy.person`, so
  the record tells the rules' decision from the person's.
- Drivers report while a run is underway, on `JourneyPath.underway`.
- `Settled` is renamed `Returned`: a run goes out and comes back with its
  outcome, so a run's entries are `Decided`, then `Returned`.

## 0.1.0

- First release: `Result` (`Run`, `Done`, `Failed`), the closed set of
  programs (`ReadFile`, `WriteFile`, `Executable`) and their `Reach`,
  `Outcome` (`Ran`, `Refused`), `FileDriver` and `ProgramDriver`,
  `ExecResult`, and `PathInRepo`.
- `JourneyPath`, `JourneyPathId`, `Airlock`, `Decision` (`Allow`, `Deny`)
  and `Entry` (`Decided`, `Settled`, `Narrowed`): `Run.next` is the one way
  to carry out a run, and each run is decided and recorded before its driver
  is reached, and recorded again before its outcome flows on. Each narrowing
  is recorded, granted or not, before the new journey path exists.
- `Tool`, `answeredBy` and `Reply`: a tool's code attached to its
  `is_tools_api` definition, and a call followed to what the model is told.
