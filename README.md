# is_airlock_api

The airlock's contract. Tools describe actions; the airlock decides and
records each one; drivers operate the world. A tool touches nothing: for
each call it returns a `Result`, which is carried through on a journey path.

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

// The airlock service's side of a journey path the docking station started;
// the airlock service holds the drivers:
final journeyPath = JourneyPath(
  id: JourneyPathId.of(startEntry), // the hash of the entry that started it
  drivers: [files, programs],
  airlock: airlock,
  rules: rules,
  suit: suit, // the OS user its programs run as
);
// Its loop, for one tool call, at that call's place in the turn:
final apex = journeyPath.at(place);
var result = writeAndFormat(file);
while (result is Action<ExecResult>) {
  result = await result.next(apex);
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
  every action is still decided and recorded at an apex. Turning a tool's
  answer into what the model is told takes no journey path.

## An action

- `Program`: a closed set, `ReadFile` (`Program.read`), `WriteFile`
  (`Program.write`), `Executable` (a `ProgramName`, with plain `Args`) and
  `MakeWebRequest` (`Program.web`, a `WebRequest` to an `Origin` through a
  named `SignIn`). Programs reach drivers, so they belong with the drivers
  and the airlock to what is trusted; a new kind of action is a new driver
  and program.
- `Action<A>`: a program, its input and the continuation, all private. Made
  only by its program (`program.run(input, then:)`), so its input is the
  program's own type. Nothing about an action shows outside; when it is
  proposed, what it would do is worked out as its `Reach`, which the
  airlock decides and records: `Reads(path)`, `Writes(file)`,
  `Starts(program, args)` or `MakesWebRequest(request, renderer)`. A rule
  grants a web request by origin and sign-in together.

## A web request

Everything a web request says is drawn from recorded journal entries, by a
renderer the record names exactly
(https://github.com/enspyrco/intersyntactic/issues/1147).

- `WebRequest`: origin, method, a `WebPath`, sign-in, headers, a `RendererName`
  such as `teams-reply`, and the `EntryId`s of the recorded entries its
  words are drawn from. It has no body, so a tool cannot put words in. The
  path and headers are checked as is_effects's `Request` checks them.
- `DecidesAndRecordsActions.renderer(name)` resolves a name to a
  `Renderer`: its `RendererId` (the sha256 of the renderer's published pub archive, as
  `pubspec.lock` records it) and the `ObjectId` of the render runner built
  with it, which pins the packages the renderer depends on as well. It is resolved before the decision, so
  `Decided` holds the whole `WebRequest` and the exact `Renderer`, never a body,
  which does not exist yet. A name that resolves to nothing is denied
  before the rules are asked.
- The airlock never talks to a renderer
  (https://github.com/enspyrco/intersyntactic/issues/1147#issuecomment-6905923566).
  A renderer subscribes to the record for `Decided` entries naming it,
  reads the entries the request draws from, and records the body, or a
  refusal when an entry is missing, in an entry of its own after the
  `Decided`. `DecidesAndRecordsActions.rendered(decided)` is the airlock
  reading that entry from the record; it is called only once `Decided` is
  kept, and what it gives is the body the web driver carries out. So the exact bytes that
  went out are in the record.
- A web request's chain in the journal: `DecidedWebRequest` (kind
  `web-request-decided`), then
  the renderer's `Rendered` (kind `rendered`), then the airlock's
  `Returned`, each naming the one before as its previous, so the journal's
  tip check lets each be written once. When the renderer does not answer
  in time, `Returned` (refused) names the `DecidedWebRequest` as its previous and
  a late `Rendered` is turned away. Each has `toJson` and a checking
  `fromJson`, given a `JsonObject` (`JsonObject.decode(text)`, from
  `checked_json`, which this package exports).
  What came back from any proposed action is recorded in full, in a
  `ReturnedProposal` (below).

A web request is an action, decided like any other: a request a tool makes
to a chat or an API. A journey path's prompts are not: the model is the
agent planning, so a prompt is not decided, and no tool is in it. How a
prompt reaches the model and is recorded is not this contract's.

## A journey path

One agent's own journey: its id, its rules `R`, and its airlock and
drivers. Its drivers act for the path, each wherever it runs.
Every entry it records is at a place `P` in a turn, which the agent loop
supplies and the airlock records; nothing here computes one.

- `JourneyPath(id:, drivers:, airlock:, rules:, suit:)`: the
  airlock service's side of a journey path, set up when the record shows
  the docking station started the path (its rules, in `admitted`) and
  loop_launcher handed it users (`assigned`). The airlock starts nothing.
  Holding the drivers
  is already the power to touch the world, so setting up a side grants
  nothing new.
- `at(place)`: the journey path's apex at that place, its tip, where its
  agent loop proposes the next action and its airlock decides it. The journey
  path checks the place's type, so whatever comes after a tool's result takes
  an `Apex` and never handles `P`. Two agents on one machine have two
  apexes; one step's two tool calls are two apexes of one journey path, at
  two places.
- `JourneyPathId`, from `is_shapes`: a journey path is named by the hash of
  the record entry that started it (`JourneyPathId.of(entryBytes)`), which
  the docking station writes, the way a `JourneyId` names a journey. So no two
  journey paths share an id, after a restart too, and nothing here mints
  one. Every entry names it.
- `action.next(apex)`, the only way an action reaches the world: it is
  proposed at the apex, and the airlock decides it; the airlock records the
  decision (`Decided`) and only then is a driver reached; the action comes
  back and the airlock records it (`Returned`), and only then does the
  continuation see it. A record that cannot be written ends the call. A
  `Decided` with no `Returned` is an action cut short. Recorded means it survives the journal crashing, not a power
  cut (https://github.com/intersyntactic/journal/pull/12).
- A `Decision` is `Allow` or `Deny(why)`, each saying who made it,
  `DecidedBy.rules` or `DecidedBy.person`; a stopped journey path's refusal
  is the person's.
- `stop()`: refuses every action on this journey path whose driver has not
  yet been reached. An action whose driver has been reached is not
  interrupted.
- `entries`: each entry once recorded, at its place. `underway`: what
  drivers report while an action is underway, for a live view, and not
  recorded. Each names its journey path and place.
- `DecidesAndRecordsActions<R, P>`: `decide`, given an action's `Reach`,
  and `record`, implemented by intersyntactic's airlock. An interface is
  named for what it can do, so `implements` reads as a true sentence
  (https://github.com/enspyrco/intersyntactic/pull/1164).

## Between the agent loop and the airlock

The agent loop and the airlock are separate services, and the record is
the only channel between them: the airlock has no door of its own
(https://github.com/enspyrco/intersyntactic/pull/1156). An action's
continuation is the tool's own code, so it stays in the loop; its program
and input go into the record as a `Proposal`, an action not yet decided,
and what came back returns through the record
(https://github.com/enspyrco/intersyntactic/pull/1157). The airlock decides
and records, and only a driver carries an action out.

- `JourneyPath.at(place)` is an apex where the journey path is, in the
  airlock service. `Apex.through(link, place:)` is one in the agent loop,
  where `link`, which `ProposesActionsThroughTheRecord`, is the transport,
  which this package does not have: it writes a `proposed` entry on the loop's journey path's chain and waits
  for the `returned` entry that names it, which loop_launcher hands the
  loop. `action.next(apex)` is the same with either, so a tool does not
  change.
- A `Proposal` (kind `proposed`) names no journey path. The journal takes
  the entries on a path's chain only from that path's loop user, so the
  airlock takes the path from the chain the entry is on, and a loop has no
  claim to make about another path. Until the journal enforces that, the
  airlock must not act on `proposed` entries.
- `Proposal.read(text)`, given a `proposed` entry's text, gives a
  `Proposal` or `Rejected(why)` and never throws, checking
  every part as its type's own `parse` does, with is_effects's codecs.
  `journeyPath.consider(proposal, place, proposed: entryId)` decides and
  records it as an action proposed at `at(place)` would be; its `Decided` and
  `Returned` name the `proposed` entry.
- `ReturnedProposal` (kind `returned`): what came back from a proposed action,
  in full, as the program's codec writes it, or the refusal, naming the
  `proposed` entry it answers. It is the one copy of what an action
  returned: a read's text, a program's output, a site's answer. The airlock
  writes it on its own chain, never the path's, which only the loop user
  writes. `ReturnedProposal.of(returned)` makes one from a `Returned` entry;
  `ReturnedProposal.refused(entryId, why)` answers a `proposed` entry that
  was `Rejected`, so its loop is answered and no other path is stalled.
- `WaitingToStart` (kind `waiting-to-start`, `{"journeyPath": <hex>}`,
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
- `WhatMayLeaveThisMachine`: a journey path's rules, which say what may
  leave this machine, to where, and as which sign-in, never whether an
  action reads or writes (https://github.com/enspyrco/intersyntactic/pull/1163).
  `modelSignInsTheLoopIsGiven` (`ModelSignInName`s; loop_launcher holds the
  credentials), `sitesTheWebDriverMayReach` (`SiteAndSignIn`: a site with
  `GoesAsSignIn(signIn)` or `GoesAsNobody`, never a null that could be read
  as any sign-in), and `programsNetwork` (`noNetworkOfTheirOwn` or
  `sharesThisMachinesNetwork`, when the site list limits only the web
  driver). Files and programs on the machine need no rule. The docking
  station writes it into `admitted`; `allowsWebRequest(reach)` is the
  airlock's check; `fromJson` refuses any key it does not know.
- An answer the loop cannot read as an outcome throws a `FormatException`
  and ends the call: whether the action reached the world is then known only
  to the airlock's record.
- Progress (`underway`) stays in the airlock service; anyone who
  subscribes to the record sees the entries.

A journey path is not narrowed from another. For one agent to do less than
another in the same journey (a reviewer that reads while the crew writes,
https://github.com/enspyrco/intersyntactic/issues/1049), the plan is that
it would be started with fewer rules, its starting entry naming its parent
and its rules, so the airlock could check they are no wider. It would still
be named by that entry's hash: a child names its parent, the way a git
commit does, never the other way round. None of that is built: today the
docking station gives a journey path whatever rules it likes.

## What the contract does not promise

An airlock guards the drivers it is given, not the journey. An agent
that joins a journey with its own drivers and its own airlock, or none, is
outside it. So "every action through these drivers is recorded" holds, and
"every action in the journey is recorded" is not this package's to promise;
the journey's rules bound our journey paths, not anyone else's.

The library imports `is_effects`, `is_shapes` and `is_content_id` and
nothing else outside the SDK; a test reads every directive's URI from Dart's parse tree and
holds it to that.
