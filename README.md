# is_airlock_api

The airlock's contract. Tools describe effects; the airlock decides and
records each one; drivers operate the world. A tool touches nothing: for
each call it returns a `Result`, which is followed on a journey path.

What an effect takes and gives back, and the drivers that carry it out, are
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

// The airlock service's side of a journey path the docking port started;
// the airlock service holds the drivers:
final journeyPath = JourneyPath(
  id: JourneyPathId.of(startEntry), // the hash of the entry that started it
  drivers: [files, programs],
  airlock: airlock,
  rules: rules,
);
// Its loop, for one tool call, at that call's place in the turn:
final apex = journeyPath.at(place);
var result = writeAndFormat(file);
while (result is Run<ExecResult>) {
  result = await result.next(apex);
}
```

## A result

- `Result<A>`: what a tool returns for a call, where `A` is its output type.
  `Run` (do this, then hand what happened to the continuation),
  `Done(value)` (the answer), or `Failed(why)` (it couldn't). `Failed` is a
  `Result<Never>`, so one fits every tool. A tool may take several runs, with
  ordinary logic between them; each is decided on its own.
- `result.map(f)`: the same result with its answer, once there is one, given
  to `f`. It reaches no driver: a run's continuation is extended, so every
  run is still decided and recorded at an apex. Turning a tool's answer into
  what the model is told takes no journey path.

## A run

- `Program`: a closed set, `ReadFile` (`Program.read`), `WriteFile`
  (`Program.write`), `Executable` (a `ProgramName`, with plain `Args`) and
  `WebSend` (`Program.web`, a `Send` to an `Origin` through a named
  `SignIn`). Programs reach drivers, so they belong with the drivers and the
  airlock to what is trusted; a new kind of effect is a new driver and
  program.
- `Run<A>`: a program, its input and the continuation, all private. Made only
  by its program, so its input is the program's own type. Nothing about a
  run shows outside; when it is proposed, what it would do is worked out
  as its `Reach`, which the airlock decides and records: `Reads(path)`,
  `Writes(file)`, `Starts(program, args)` or `Sends(send, renderer)`. A
  rule grants a send by origin and sign-in together.

## A send

Everything a send says is drawn from recorded journal entries, by a
renderer the record names exactly
(https://github.com/enspyrco/intersyntactic/issues/1147).

- `Send`: origin, method, a `WebPath`, sign-in, headers, a `RendererName`
  such as `teams-reply`, and the `EntryId`s of the recorded entries its
  words are drawn from. It has no body, so a tool cannot put words in. The
  path and headers are checked as is_effects's `Request` checks them.
- `Airlock.renderer(name)` resolves a name to a `Renderer`: its
  `RendererId` (the sha256 of the renderer's published pub archive, as
  `pubspec.lock` records it) and the `ObjectId` of the render runner built
  with it, which pins the packages the renderer depends on as well. It is resolved before the decision, so
  `Decided` holds the whole `Send` and the exact `Renderer`, never a body,
  which does not exist yet. A name that resolves to nothing is denied
  before the rules are asked.
- The airlock never talks to a renderer
  (https://github.com/enspyrco/intersyntactic/issues/1147#issuecomment-6905923566).
  A renderer follows the journal for `Decided` entries naming it, reads
  the entries the send draws from, and records the body, or a refusal when
  an entry is missing, in an entry of its own after the `Decided`.
  `Airlock.rendered(decided)` is the airlock following the journal to that
  entry; it is called only once `Decided` is kept, and what it gives is
  what is sent. So the exact bytes sent are in the record.
- A send's chain in the journal: `DecidedSend` (kind `send-decided`), then
  the renderer's `Rendered` (kind `rendered`), then the airlock's
  `Returned`, each following the one before, so the journal's tip check
  lets each be written once. When the renderer does not answer in time,
  `Returned` (refused) follows the `DecidedSend` directly and a late
  `Rendered` is turned away. Each has `toJson` and a checking `fromJson`.
  Only a send's entries have a wire form: other runs' entries still name
  what a run reached and why, never a file's text or a program's output.

A send is an effect, decided like any other: what a tool sends to a chat or
an API. A journey path's prompts are not: the model is the agent planning,
so a prompt is not decided, and no tool is in it. How a prompt is sent and
recorded is not this contract's.

## A journey path

One agent's own journey: its id, its rules `R`, and its airlock and
drivers. Its drivers act as the journey's user, each wherever it runs.
Every entry it records is at a place `P` in a turn, which the agent loop
supplies and the airlock records; nothing here computes one.

- `JourneyPath(id:, drivers:, airlock:, rules:)`: the airlock service's
  side of a journey path, set up when loop_launcher says the docking port
  has started the path (`PathStarted`). The airlock starts nothing. Holding the drivers
  is already the power to touch the world, so setting up a side grants
  nothing new.
- `at(place)`: the journey path's apex at that place, its tip, where its
  agent loop proposes the next run and its airlock decides it. The journey
  path checks the place's type, so whatever follows a tool's result takes
  an `Apex` and never handles `P`. Two agents on one machine have two
  apexes; one step's two tool calls are two apexes of one journey path, at
  two places.
- `JourneyPathId`, from `is_shapes`: a journey path is named by the hash of
  the record entry that started it (`JourneyPathId.of(entryBytes)`), which
  the docking port writes, the way a `JourneyId` names a journey. So no two
  journey paths share an id, after a restart too, and nothing here mints
  one. Every entry names it.
- `run.next(apex)`, the only way a run reaches the world: it is proposed at
  the apex, and the airlock decides it; the airlock records the decision (`Decided`) and only then is
  a driver reached; the run comes back and the airlock records it
  (`Returned`), and only then does the continuation see it. A record that
  cannot be written ends the call. A `Decided` with no `Returned` is a run
  cut short. Recorded means it survives the journal crashing, not a power
  cut (https://github.com/intersyntactic/journal/pull/12).
- A `Decision` is `Allow` or `Deny(why)`, each saying who made it,
  `DecidedBy.rules` or `DecidedBy.person`; a stopped journey path's refusal
  is the person's.
- `stop()`: refuses every run on this journey path whose driver has not
  yet been reached. A run whose driver has been reached is not interrupted.
- `entries`: each entry once recorded, at its place. `underway`: what
  drivers report while a run is underway, for a live view, and not
  recorded. Each names its journey path and place.
- `Airlock<R, P>`: `decide`, given a run's `Reach`, and `record`,
  implemented by intersyntactic's airlock.

## Between the agent loop and the airlock

The agent loop and the airlock are separate services, and what passes
between them is a message with a type (RULINGS, "No server"). A run's
continuation is the tool's own code, so it stays in the loop; its program
and input go to the airlock as a `Proposal`, an effect not yet decided, and
the outcome comes back. The airlock decides and records, and only a driver
carries an effect out (RULINGS: "the airlock operates nothing").

- `JourneyPath.at(place)` is an apex where the journey path is, in the
  airlock service. `Apex.through(link, journeyPath:, token:, place:)` is one
  in the agent loop, over an `AirlockLink`, the transport (a socket, say),
  which this package does not have. `run.next(apex)` is the same with
  either, so a tool does not change.
- `PathStarted(journeyPath, rules:, stopped:)`: the docking port starts
  journey paths, and records that it did; loop_launcher follows the journal
  for those entries and tells the airlock service, which holds the drivers
  and so sets up its own side of the path (`JourneyPath`). The answer is
  `Ready`, with the token loop_launcher gives the loop it launches for the
  path, or `Rejected`. The airlock service takes this only from
  loop_launcher's OS user. Sent again after either service restarts: a path whose
  side the airlock service no longer holds is set up anew under the same
  id, and one it holds gets a new token (`JourneyPath.reissue`), after
  which the old one is rejected. `stopped` keeps the person's stop across a
  restart, and nothing un-stops a path. A live path keeps the rules it had.
- `PathToken`: minted when the airlock service sets up its side of a path,
  and handed only to loop_launcher, for the loop it launches to put in
  every `Proposal`. The OS user on the socket cannot tell one journey path from
  another, since an agent's paths share its user; the token can. It is
  compared in constant time, never with `==`, never recorded, and its
  `toString` does not show it.
- `Proposal.read(json)` gives a `Proposal` or `Rejected(why)`, checking
  every part as its type's own `parse` does, with is_effects's codecs.
  `journeyPath.consider(proposal, place)` decides and records it as a run
  proposed at `at(place)` would be, once it shows the path's token, giving
  `Considered` or `Rejected`.
- A `Rejected` request is in no journey path's record, so a stranger cannot
  write into one. The service records it in the airlock's own chain, with
  the journey path it claimed and the socket peer's OS user, never the
  token: a wrong token is the attack the token is there to stop, and it
  should leave a trace. Only processes allowed to reach the airlock's socket
  can send at all, so how much a stranger can add there is bounded by who
  can connect; nothing here limits the rate.
- An answer the loop cannot read as an outcome throws a `FormatException`
  and ends the call: whether the run reached the world is then known only
  to the airlock's record.
- Progress (`underway`) stays in the airlock service; the journal's
  `follow` gives `entries` to anyone.

A journey path is not narrowed from another. For one agent to do less than
another in the same journey (a reviewer that reads while the crew writes,
https://github.com/enspyrco/intersyntactic/issues/1049), the plan is that
it would be started with fewer rules, its starting entry naming its parent
and its rules, so the airlock could check they are no wider. It would still
be named by that entry's hash: a child names its parent, the way a git
commit does, never the other way round. None of that is built: today the
docking port gives a journey path whatever rules it likes.

## What the contract does not promise

An airlock guards the drivers it is given, not the journey. An agent
that joins a journey with its own drivers and its own airlock, or none, is
outside it. So "every effect through these drivers is recorded" holds, and
"every effect in the journey is recorded" is not this package's to promise;
the journey's rules bound our journey paths, not anyone else's.

The library imports `is_effects`, `is_shapes` and `is_content_id` and
nothing else outside the SDK; a test reads every directive's URI from Dart's parse tree and
holds it to that.
