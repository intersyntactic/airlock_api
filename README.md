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

// The service that starts a journey path, which holds the drivers:
final journeyPath = JourneyPath.start(
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
  to `f`. It carries out nothing: a run's continuation is extended, so every
  run is still decided and recorded at an apex. Turning a tool's answer into
  what the model is told takes no journey path.

## A run

- `Program`: a closed set, `ReadFile` (`Program.read`), `WriteFile`
  (`Program.write`), `Executable` (a `ProgramName`, with plain `Args`) and
  `WebPost` (`Program.web`, a `Post` to an `Origin` through a named
  `SignIn`). Programs reach drivers, so they belong with the drivers and the
  airlock to what is trusted; a new kind of effect is a new driver and
  program.
- `Run<A>`: a program, its input and the continuation, all private. Made only
  by its program, so its input is the program's own type. Nothing about a
  run shows outside; when it is carried out, what it would do is worked out
  as its `Reach`, which the airlock decides and records: `Reads(path)`,
  `Writes(file)`, `Starts(program, args)` or `Sends(post, renderer)`. A
  rule grants a send by origin and sign-in together.

## A post

Everything a post says is drawn from recorded journal entries, by a
renderer the record names exactly
(https://github.com/enspyrco/intersyntactic/issues/1147).

- `Post`: origin, method, a `WebPath`, sign-in, headers, a `RendererName`
  such as `teams-reply`, and the `EntryId`s of the recorded entries its
  words are drawn from. It has no body, so a tool cannot put words in. The
  path and headers are checked as is_effects's `Request` checks them.
- `Renderers`: implemented by the service that starts journey paths.
  `find` resolves a name to a `Renderer`, its `RendererId` (the hash of its
  source) and the `ObjectId` of the executable run. `render` reads each
  entry from the journal, checks it, and runs the renderer as its own
  program with no network and no secrets: entries in, body out.
- The renderer is resolved before the decision, so `Decided` holds the
  whole `Post` and the exact `Renderer`, never a body, which does not exist
  yet. A name that resolves to nothing is denied before the rules are
  asked. The body is drawn only once `Decided` is kept; an entry the
  journal does not hold refuses the post, and nothing is sent.

A post is an effect, decided like any other: what a tool posts to a chat or
an API. A journey path's prompts are not: the model is the agent planning,
so a prompt is not decided, and no tool is in it. How a prompt is sent and
recorded is not this contract's.

## A journey path

One agent's own journey: its id, its rules `R`, and its airlock and
drivers. Its drivers act as the journey's user, each wherever it runs.
Every entry it records is at a place `P` in a turn, which the agent loop
supplies and the airlock records; nothing here computes one.

- `JourneyPath.start(id:, drivers:, airlock:, rules:, renderers:)`: by the
  service that starts a journey path. With no `renderers`, every post is
  denied. Holding the drivers is already the power to touch
  the world, so starting a journey path grants nothing new.
- `at(place)`: the journey path's apex at that place, its tip, where its
  agent loop and airlock carry out the next run. The journey path checks
  the place's type, so whatever follows a tool's result takes an `Apex` and
  never handles `P`. Two agents on one machine have two apexes; one step's
  two tool calls are two apexes of one journey path, at two places.
- `JourneyPathId`, from `is_shapes`: a journey path is named by the hash of
  the record entry that started it (`JourneyPathId.of(entryBytes)`), which
  whoever starts it writes, the way a `JourneyId` names a journey. So no two journey
  paths share an id, after a restart too, and nothing here mints one. Every
  entry carries it.
- `run.next(apex)`, the only way to carry out a run: the airlock
  decides it; the airlock records the decision (`Decided`) and only then is
  a driver reached; the run comes back and the airlock records it
  (`Returned`), and only then does the continuation see it. A record that
  cannot be written ends the call. A `Decided` with no `Returned` is a run
  cut short. Recorded means it survives the journal crashing, not a power
  cut (https://github.com/intersyntactic/journal/pull/12).
- A `Decision` is `Allow` or `Deny(why)`, each saying who made it,
  `DecidedBy.rules` or `DecidedBy.person`; a stopped journey path's refusal
  is the person's.
- `stop()`: refuses every run not yet carried out on this journey path. A
  run whose driver has been reached is not interrupted.
- `entries`: each entry once recorded, at its place. `underway`: what
  drivers report while a run is underway, for a live view, and not
  recorded. Each names its journey path and place.
- `Airlock<R, P>`: `decide`, given a run's `Reach`, and `record`,
  implemented by intersyntactic's airlock.

A journey path is not narrowed from another. For one agent to do less than
another in the same journey (a reviewer that reads while the crew writes,
https://github.com/enspyrco/intersyntactic/issues/1049), the plan is that
it would be started with fewer rules, its starting entry naming its parent
and its rules, so the airlock could check they are no wider. It would still
be named by that entry's hash: a child names its parent, the way a git
commit does, never the other way round. None of that is built: today the
service that starts a journey path gives it whatever rules it likes.

## What the contract does not promise

An airlock guards the drivers it is started with, not the journey. An agent
that joins a journey with its own drivers and its own airlock, or none, is
outside it. So "every effect through these drivers is recorded" holds, and
"every effect in the journey is recorded" is not this package's to promise;
the journey's rules bound our journey paths, not anyone else's.

The library imports `is_effects`, `is_shapes` and `is_content_id` and
nothing else outside the SDK; a test reads every directive's URI from Dart's parse tree and
holds it to that.
