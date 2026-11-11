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
  drivers: [files, programs, network],
  airlock: airlock,
  rules: rules,
);
var result = writeAndFormat(file);
while (result is Run<ExecResult>) {
  result = await result.next(journeyPath);
}
```

## A result

- `Result<A>`: what a tool returns for a call, where `A` is its output type.
  `Run` (do this, then hand what happened to the continuation),
  `Done(value)` (the answer), or `Failed(why)` (it couldn't). `Failed` is a
  `Result<Never>`, so one fits every tool. A tool may take several runs, with
  ordinary logic between them; each is decided on its own.

## A run

- `Program`: a closed set, `ReadFile` (`Program.read`), `WriteFile`
  (`Program.write`) and `Executable` (a `ProgramName`, with plain `Args`).
  Programs reach drivers, so they belong with the drivers and the airlock to
  what is trusted; a new kind of effect is a new driver and program.
- `Run<A>`: a program, its input and the continuation, all private. Made only
  by its program, so its input is the program's own type. Outside, a run
  shows only its `Reach`, for the airlock: `Reads(path)`, `Writes(file)` or
  `Starts(program, args)`.

Nothing here sends out of the home. A journey path's rules say what may
leave, to where, and through which sign-in; each journey path's own loop
holds only the sign-ins its rules allow, so its model calls can go nowhere
else.

## A journey path

One agent's own journey: its id, its rules, and its airlock and drivers.
Its apex is its growing tip, where its next effect happens; two agents on
one machine have two apexes. Its drivers are those of the machine its apex
is on, acting as the journey's user.

- `JourneyPath.start(id:, drivers:, airlock:, rules:)`: by the host. Holding
  the drivers is already the power to touch the world, so starting a journey
  path grants nothing new.
- `await narrowed(fewer, id:)`: a journey path under rules the airlock finds
  allow no more; null otherwise. Everyone but the host gets journey paths
  this way. Recorded either way, as a `Narrowed` entry, before the new one
  exists: the record's tree of journey paths is these entries, and a refusal
  is an attempt to widen.
- `JourneyPathId.parse(raw)`: given by whoever starts or narrows a journey
  path, and carried by every entry it records. A blank one parses to null;
  `narrowed` refuses an id already asked for under the same started journey
  path, and a narrowing whose record throws has used its id up. Ids from
  before a restart are the host's to keep apart.
- `run.next(journeyPath)`, the only way to carry out a run: the airlock
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
- `entries`: each entry once recorded. `underway`: what drivers report while
  a run is underway, for a live view, and not recorded. Both come from this
  journey path and every one narrowed from it, each naming its journey path.
- `Airlock<R>`: `decide`, `narrows` and `record`, implemented by
  intersyntactic's airlock.

## What the contract does not promise

An airlock guards the drivers it is started with, not the journey. An agent
that joins a journey with its own drivers and its own airlock, or none, is
outside it. So "every effect through these drivers is recorded" holds, and
"every effect in the journey is recorded" is not this package's to promise;
the journey's rules bound our journey paths, not anyone else's.

The library imports `is_effects` and nothing else outside the SDK; a test
reads every directive's URI from Dart's parse tree and holds it to that.
