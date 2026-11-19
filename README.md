# is_airlock_api

The airlock's contract. Tools describe actions; the airlock decides and
records each one; drivers operate the world. A tool touches nothing: for
each call it returns a `Result`, which is carried through on a trajectory.

What an action takes and gives back, and the drivers that carry it out, are
`is_effects`'s, so a driver never sees this package. Joining an
`is_tools_api` definition to what a tool does is `is_tool`'s.

```dart
final dart = Executable.parse('dart')!;

/// Writes [file], then formats it.
Result<ExecResult> writeAndFormat(FileText file) => Program.write.runOrRefusal(
  file,
  then: (wrote) =>
      dart.runOrRefusal(Args(['format', file.path.value]), then: Done.new),
);

// The airlock service's side of a trajectory the docking station started;
// the airlock service holds the drivers:
final trajectory = Trajectory(
  id: TrajectoryId.of(startEntry), // the hash of the entry that started it
  drivers: [files, programs],
  airlock: airlock,
  rules: rules,
  suit: suit, // the OS user its programs run as
);
// Its loop, for one tool call, at that call's place in the turn:
final crux = trajectory.at(place);
var result = writeAndFormat(file);
while (result is Action<ExecResult>) {
  result = await result.next(crux);
}
```

## A result

- `Result<A>`: what a tool returns for a call, where `A` is its output type.
  `Action` (do this, then hand what happened to the continuation),
  `Done(value)` (the answer), or `Failed(why)` (it couldn't). `Failed` is a
  `Result<Never>`, so one fits every tool. A tool may take several actions,
  with ordinary logic between them; each is decided on its own.
- `result.map(f)`: the same result with its answer, once there is one, given
  to `f`. It reaches no driver: an action's continuation is extended, so
  every action is still decided and recorded at a crux. Turning a tool's
  answer into what the model is told takes no trajectory.

## An action

- `Program`: a closed set, `ReadFile` (`Program.read`), `WriteFile`
  (`Program.write`), `Executable` (a `ProgramName`, with plain `Args`),
  `MakeWebRequest` (`Program.web`, a `WebRequest` to an `Origin` through a
  named `SignIn`) and `AskTheModel` (`Program.askTheModel`, below). Programs reach drivers, so they belong with the drivers
  and the airlock to what is trusted; a new kind of action is a new driver
  and program.
- `Action<A>`: a program, its input and the continuation, all private. Made
  only by its program (`program.run(input, then:)`), so its input is the
  program's own type. Nothing about an action shows outside; when it is
  proposed, what it would do is worked out as its `Reach`, which the
  airlock decides and records: `Reads(path)`, `Writes(file)`,
  `Starts(program, args)`, `MakesWebRequest(request)` or
  `CallsTheModel(call)`. A rule grants a web request by origin and sign-in
  together, and a model call by its model sign-in.

## A web request

A web request carries the exact bytes it sends, so the airlock decides
what will be sent, not the code that will produce it, and those bytes must
come from the record.

- `WebRequest`: origin, method, a `WebPath`, sign-in, headers, the exact
  `body`, the `projection` it is drawn by, and `drawnFrom`, the recorded
  entry it is drawn from. The path and headers are checked as is_effects's
  `Request` checks them. The decision holds the whole request, body and
  all.
- `Projection`: how a body is drawn from a recorded entry, one pure
  function each, which the loop builds the body with and the airlock checks
  it by. `teamsMessageFromModelReply` (`teams-message-from-model-reply`)
  draws `{"type":"message","text":<text>}` (Dart's `jsonEncode`, those two
  keys in that order, no whitespace, the text as UTF-8) from a
  `outcome-of-proposed-action` whose result ran to text: a model's
  reply.
- Once allowed, the airlock reads `drawnFrom` through
  `DecidesAndRecordsActions.recordedOn`, which gives it only when it
  belongs to the trajectory, draws the body by the projection, and reaches
  the web driver only when that is byte-identical to `body`. Anything else
  is refused, each for its own reason, and nothing is sent. So a loop can
  send only what its projection makes of what is recorded, and the words
  in a model's reply only as the airlock recorded them.
- A web request's chain in the logbook: `AirlockDecisionOnWebRequest`
  (kind `airlock-decision-on-web-request`) starts it, since the proposal's
  chain is its loop user's alone, and the airlock's
  `outcome-of-proposed-action` follows it. The decision names its
  proposal, so no two start byte-identical chains, which the logbook
  service refuses. It has `toJson` and a checking `fromJson`.

A web request is an action, decided like any other: a request a tool makes
to a chat or an API.

## A model call

The model is outside the station: the case's words leave the machine with
every call, so a model call is an action, the one the loop proposes for
itself rather than drawing from an intent in the model's reply
(https://github.com/enspyrco/intersyntactic/pull/1168, replacing the ruling
that the model is the agent planning and is not decided). The loop holds no
sign-in and has no network; the model driver, holding every model sign-in,
makes the call.

- The loop records what it will send first: each text, the system prompt
  and the request, as `ModelRequestPiece` entries (kind
  `model-request-piece`, `{"text"}`), then a `ModelRequest` (kind
  `model-request`) naming them: `systemPrompt` and `request`, each a
  `RecordedText` (its pieces in order and the sha256 of its UTF-8 bytes),
  and `builtFrom`, the turns they were drawn from. Pieces are named by
  entry, so each was recorded before it is sent; repeated history is still
  stored once, as one object under many entries.
- `AskTheModel` (proposed as `model`) takes a `ModelCall`: the
  `ModelSignInName` it goes as, the `ModelName`, and the `ModelRequest`
  entry. Its reach, `CallsTheModel`, is decided by the sign-in.
- Once allowed, the airlock reads the request and each piece with
  `DecidesAndRecordsActions.recordedOn(trajectory, entry)`, which gives an
  entry only when it belongs to the trajectory: on its own chain, or the
  airlock's result for one of its proposals. So no loop can have another's
  conversation sent. It joins each text and checks its sha256
  (`RecordedText.join`), and hands the driver (is_effects's
  `AsksTheModel`) exactly those texts. Anything missing, elsewhere, or not
  joining refuses the call before the driver is reached, each for its own
  reason. The reply streams as `ReplyArriving` in `underway`, never
  recorded; the whole `ModelReply` is the outcome, recorded once.
- What the record proves stops at the driver: the texts it holds are the
  texts the model driver was given. A driver that runs a program (such as
  `claude -p`) sends what that program sends, which may add context of its
  own on the way to the model provider.

## A trajectory

One agent's own line of work in a mission: its id, its rules `R`, and its airlock and
drivers. Its drivers act for the path, each wherever it runs.
Every entry it records is at a place `P` in a turn, which the agent loop
supplies and the airlock records; nothing here computes one.

- `Trajectory(id:, drivers:, airlock:, rules:, suit:)`: the
  airlock service's side of a trajectory, set up when the record shows
  the docking station started the path (its rules, in `admitted`) and
  loop_launcher handed it users (`assigned`). The airlock starts nothing.
  Holding the drivers
  is already the power to touch the world, so setting up a side grants
  nothing new.
- `at(place)`: the trajectory's crux at that place: its agent loop, the one
  holder that extends the trajectory, where the next action is proposed and
  its airlock decides it
  (https://github.com/enspyrco/intersyntactic/pull/1168). The trajectory
  checks the place's type, so whatever comes after a tool's result takes a
  `Crux` and never handles `P`. Two agents on one machine have two cruxes;
  one step's two tool calls go through one trajectory's crux, at two places.
- `TrajectoryId`, from `is_shapes`: a trajectory is named by the hash of
  the record entry that started it (`TrajectoryId.of(entryBytes)`), which
  the docking station writes, the way a `MissionId` names a mission. So no two
  trajectories share an id, after a restart too, and nothing here mints
  one. Every entry names it.
- `action.next(crux)`, the only way an action reaches the world: it is
  proposed at the crux, and the airlock decides it; the airlock records the
  decision (`AirlockDecisionOnAction`) and only then is a driver reached;
  the airlock records the action's result, or why it was refused, and only
  then does the continuation see it. A record that cannot be written ends
  the call. A decision with no result after it is an action cut short. Recorded means it
  survives the logbook service crashing, not a power cut
  (https://github.com/intersyntactic/logbook/pull/12).
- A `Decision` is `Allow` or `Deny(why)`, each saying who made it,
  `DecidedBy.rules` or `DecidedBy.person`; a stopped trajectory's refusal
  is the person's. `reliedOn` names the logbook entries the airlock read
  to decide beyond the rules, such as the lease of the bot the trajectory
  may post as.
- `stop()`: refuses every action on this trajectory whose driver has not
  yet been reached. An action whose driver has been reached is not
  interrupted.
- `decisions`: each decision once recorded. `results`: each result, with
  the decision it follows, once recorded. `underway`: what drivers report
  while an action is underway, for a live view, and not recorded. Each
  names its trajectory and place.
- `DecidesAndRecordsActions<R, P>`: `decide`, given the trajectory and an
  action's `Reach`, so the airlock can read what holds for that trajectory
  now, then `recordDecision(decision)` and `recordResult(decision, result,
  resultAsJson:)`, implemented by intersyntactic's airlock. An interface is
  named for what it can do, so `implements` reads as a true sentence
  (https://github.com/enspyrco/intersyntactic/pull/1164).

## Between the agent loop and the airlock

The agent loop and the airlock are separate services, and the record is
the only channel between them: the airlock has no door of its own
(https://github.com/enspyrco/intersyntactic/pull/1156). An action's
continuation is the tool's own code, so it stays in the loop; its program
and input go into the logbook as an `ActionProposedByAgentLoop`, an action
not yet decided,
and what came back returns through the record
(https://github.com/enspyrco/intersyntactic/pull/1157). The airlock decides
and records, and only a driver carries an action out.

- `Trajectory.at(place)` is a crux where the trajectory is, in the
  airlock service. `Crux.through(link, turn:)` is one in the agent loop,
  one per turn: it proposes each action of the turn at the next
  `PlaceInTrajectory(turn, step)`, from step 0, so the model call, each
  action of a tool it asks for and the reply each get their own place, and
  a restarted loop gives each the same place again. `link`, which
  `ProposesActionsThroughTheRecord`, is the transport, which this package
  does not have: `writeProposal(body)` writes an
  `action-proposed-by-agent-loop` logbook entry on the loop's trajectory's
  chain and gives back the id the logbook gave it, and
  `outcomeNaming(id)` waits for the `outcome-of-proposed-action` logbook
  entry that names it, which loop_launcher hands the loop. This package
  joins the two and refuses an outcome naming another proposal, so a loop
  never works out an id. `action.next(crux)` is the same with either, so a
  tool does not change.
- `PlaceInTrajectory`: a turn (one model call and what it caused) and a
  step within it, written `[turn, step]`, ordered by turn then step.
  `parse` gives null for anything else, and a proposal without one is
  `Rejected('not a place')`.
- An `ActionProposedByAgentLoop` (kind `action-proposed-by-agent-loop`)
  names no trajectory. The logbook service
  takes the entries on a path's chain only from that path's loop user, so
  the airlock takes the path from the chain the entry is on, and a loop has
  no claim to make about another path.
- `ActionProposedByAgentLoop.read(json)` gives an
  `ActionProposedByAgentLoop` or `Rejected(why)`, checking every part as
  its type's own `parse` does, with is_effects's codecs.
  `trajectory.consider(proposal, place, proposed: entryId)` decides and
  records it as an action proposed at `at(place)` would be; its decision
  and its result both name the proposal.
- A result (kind `outcome-of-proposed-action`, body
  `{"proposed": <hex>, "result": <outcome>}`): what came back from a
  proposed action, in full, as the program's codec writes it, or why it was
  refused. It is the one copy of what an action returned: a read's text, a
  program's output, a site's answer, a model's reply. The airlock writes it
  on the decision's chain, never the path's, which only the loop user
  writes. `outcomeOfProposedActionToJson(proposed, resultAsJson)` writes
  one, `proposalRejectedToJson(proposed, why)` answers a proposal that was
  `Rejected`, so its loop is answered and no other path is stalled, and
  `readOutcomeOfProposedAction(json)` reads one back as
  `(proposed:, result:)`, or null when it is not one.
- `WaitingToStart` (kind `waiting-to-start`, `{"trajectory": <hex>}`,
  read strictly): loop_launcher records it once, on a chain of its own,
  when a path that has no `assigned` entry yet has to wait for room. Its
  `assigned` ends the wait. Why it waits goes to the operator only, so the
  entry carries no reason.
- `LoopUser` (`loop-<n>`) and `Suit` (`suit-<n>`): the OS users
  loop_launcher hands each path from pools infra makes ahead of time, and
  records in the path's `assigned` entry. The path's loop runs as its loop
  user, and its programs run as its suit, the identity the path wears,
  contained or open (https://github.com/enspyrco/intersyntactic/pull/1158):
  the airlock service gives the path a program driver that runs as it.
- An answer the loop cannot read as an outcome throws a `FormatException`
  and ends the call: whether the action reached the world is then known only
  to the airlock's record.
- Progress (`underway`) stays in the airlock service; anyone who
  subscribes to the record sees the entries.

A trajectory is not narrowed from another. For one agent to do less than
another in the same mission (a reviewer that reads while the others write,
https://github.com/enspyrco/intersyntactic/issues/1049), the plan is that
it would be started with fewer rules, its starting entry naming its parent
and its rules, so the airlock could check they are no wider. It would still
be named by that entry's hash: a child names its parent, the way a git
commit does, never the other way round. None of that is built: today the
docking station gives a trajectory whatever rules it likes.

## What the contract does not promise

An airlock guards the drivers it is given, not the mission. An agent
that joins a mission with its own drivers and its own airlock, or none, is
outside it. So "every action through these drivers is recorded" holds, and
"every action in the mission is recorded" is not this package's to promise;
the mission's rules bound our trajectories, not anyone else's.

The library imports `is_effects`, `is_shapes` and `is_content_id` and
nothing else outside the SDK; a test reads every directive's URI from Dart's parse tree and
holds it to that.
