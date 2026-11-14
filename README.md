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

// The host, which holds the drivers:
final journeyPath = JourneyPath.start(
  id: JourneyPathId.parse('fix-login/agent-1')!,
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
  `WebRequest` (`Program.web`, a `Request` to an `Origin` through a named
  `SignIn`). Programs reach drivers, so they belong with the drivers and the
  airlock to what is trusted; a new kind of effect is a new driver and
  program.
- `Run<A>`: a program, its input and the continuation, all private. Made only
  by its program, so its input is the program's own type. Outside, a run
  shows only its `Reach`, for the airlock: `Reads(path)`, `Writes(file)`,
  `Starts(program, args)` or `Sends(origin, signIn)`. A rule grants a send
  by origin and sign-in together; `Sends` never holds the body, so what
  was said cannot reach the record through a reach.

A `WebRequest` is an effect, decided like any other: what a tool posts to a
chat or an API. A journey path's prompts are not: the model is the agent
planning, so a prompt is not decided, and no tool is in it. How a prompt
is sent and recorded is not this contract's.

## A journey path

One agent's own journey: its id, its rules `R`, and its airlock and
drivers. Its drivers act as the journey's user, each wherever it runs.
Every entry it records is at a place `P` in a turn, which the host supplies
and the airlock records; nothing here computes one.

- `JourneyPath.start(id:, drivers:, airlock:, rules:)`: by the host. Holding
  the drivers is already the power to touch the world, so starting a journey
  path grants nothing new.
- `await narrowed(fewer, id:, at:)`: a journey path under rules the airlock
  finds allow no more; null otherwise. Everyone but the host gets journey
  paths this way. Recorded either way, at `at`, as a `Narrowed` entry,
  before the new one exists: the record's tree of journey paths is these
  entries, and a refusal is an attempt to widen.
- `at(place)`: the journey path's apex at that place, its tip, where its
  agent loop and airlock carry out the next run. The journey path checks
  the place's type, so whatever follows a tool's result takes an `Apex` and
  never handles `P`. Two agents on one machine have two apexes; one step's
  two tool calls are two apexes of one journey path, at two places.
- `JourneyPathId.parse(raw)`: given by whoever starts or narrows a journey
  path, and carried by every entry it records. A blank one parses to null;
  `narrowed` refuses an id already asked for under the same started journey
  path, and a narrowing whose record throws has used its id up. Ids from
  before a restart are the host's to keep apart.
- `run.next(apex)`, the only way to carry out a run: the airlock
  decides it; the airlock records the decision (`Decided`) and only then is
  a driver reached; the run comes back and the airlock records it
  (`Returned`), and only then does the continuation see it. A record that
  cannot be written ends the call. A `Decided` with no `Returned` is a run
  cut short.
- A `Decision` is `Allow` or `Deny(why)`, each saying who made it,
  `DecidedBy.rules` or `DecidedBy.person`; a stopped journey path's refusal
  is the person's.
- `stop()`: refuses every run not yet carried out, on this journey path and
  every one narrowed from it. A run whose driver has been reached is not
  interrupted.
- `entries`: each entry once recorded, at its place. `underway`: what
  drivers report while a run is underway, for a live view, and not
  recorded. Both come from this journey path and every one narrowed from
  it, each naming its journey path and place.
- `Airlock<R, P>`: `decide`, `narrows` and `record`, implemented by
  intersyntactic's airlock.

## What the contract does not promise

An airlock guards the drivers it is started with, not the journey. An agent
that joins a journey with its own drivers and its own airlock, or none, is
outside it. So "every effect through these drivers is recorded" holds, and
"every effect in the journey is recorded" is not this package's to promise;
the journey's rules bound our journey paths, not anyone else's.

The library imports `is_effects` and nothing else outside the SDK; a test
reads every directive's URI from Dart's parse tree and holds it to that.
