# is_airlock_api

The airlock's contract. Tools describe effects; the airlock decides and
records each one; drivers operate the world. A tool's code touches nothing:
for each call it returns a `Result`, which is followed on a journey path.

```dart
const dart = Executable('dart');

final writeAndFormat = ToolSpec<FileText, ExecResult>(
  name: 'write_and_format',
  description: 'Writes a Dart file, then formats it.',
  input: Input.fields2(
    Field('path', Schema.string()),
    Field('text', Schema.string()),
    (String path, String text) => FileText(PathInRepo.parse(path)!, text),
  ),
  output: ExecResult.output,
).answeredBy(
  (file) => Program.write.runOrRefusal(
    file,
    then: (wrote) =>
        dart.runOrRefusal(Args(['format', file.path.value]), then: Done.new),
  ),
);

// The host, which holds the drivers:
final journeyPath = JourneyPath.start(
  id: const JourneyPathId('fix-login/agent-1'),
  drivers: [files, programs],
  airlock: airlock,
  rules: rules,
);
final reply = await writeAndFormat.reply(input, journeyPath);
// reply.forModel, reply.isError: the call's tool result.
```

## A call

- `Result<A>`: what a tool's code returns, where `A` is the tool's output
  type. `Run` (do this, then hand what happened to the continuation),
  `Done(value)` (the answer), or `Failed(why)` (it couldn't). `Failed` is a
  `Result<Never>`, so one fits every tool.
- `answeredBy`: attaches code to an `is_tools_api` `ToolSpec<I, O>`, giving a
  `Tool<I, O>`. The code must take the definition's `I` and answer with its
  `O`, or it does not compile.
- `Tool.reply(json, journeyPath)`: reads the input with the definition,
  follows the runs on the journey path, and renders `Done` with the
  definition's `Output`. An input the definition refuses, and a `Failed`, are
  replies with `isError`.

## A run

- `Program`: a closed set, `ReadFile` (`Program.read`), `WriteFile`
  (`Program.write`) and `Executable('git')` with plain `Args`. Programs reach
  drivers, so they belong with the drivers and the airlock to what is
  trusted; a new kind of effect is a new driver and program here.
- `Run<A>`: a program, its input and the continuation, all private. Made only
  by its program, so its input is the program's own type. Outside, a run
  shows only its `Reach` (`Reads`, `Writes`, `Starts`), for the airlock.
- `PathInRepo`: a path inside the repo, never leaving it, made only by
  `parse`. Reads, writes and a program's folder take one, so a path out of
  the repo never reaches a driver.
- `Outcome<O>`: `Ran(output)` or `Refused(why)`.

## A journey path

One agent's own journey: its id, its rules, and its airlock and drivers.
Its apex is its growing tip, where its next effect happens; two agents on
one machine have two apexes. Its drivers are those of the machine its apex
is on, acting as the journey's user.

- `JourneyPath.start(id:, drivers:, airlock:, rules:)`: by the host. Holding
  the drivers is already the power to touch the world, so starting a journey
  path grants nothing new.
- `narrowed(fewer, id:)`: a journey path under rules the airlock finds allow
  no more; null otherwise. Everyone but the host gets journey paths this way.
- `JourneyPathId`: given by whoever starts or narrows a journey path, and
  carried by every entry it records, so a record that outlives the objects
  still says which journey path each run was on.
- `run.next(journeyPath)`, the only way to carry out a run: the airlock
  decides it; the airlock records the decision (`Decided`) and only then is
  a driver reached; the airlock records what became of it (`Settled`) and
  only then does the continuation see it. A record that cannot be written
  ends the call, so no driver is reached without a recorded decision and no
  outcome flows on unrecorded. A `Decided` with no `Settled` is a run cut
  short.
- `stop()`: refuses every run not yet carried out, on this journey path and
  every one narrowed from it. A run whose driver has been reached is not
  interrupted.
- `entries`: each entry once recorded, from this journey path and every one
  narrowed from it, for a live view.
- `Airlock<R>`: `decide`, `narrows` and `record`, implemented by
  intersyntactic's airlock.

## What the contract does not promise

An airlock guards the drivers it is started with, not the journey. An agent
that joins a journey with its own drivers and its own airlock, or none, is
outside it. So "every effect through these drivers is recorded" holds, and
"every effect in the journey is recorded" is not this package's to promise;
the journey's rules bound our journey paths, not anyone else's.

The library imports `is_tools_api`, `checked_json` and `path`, and no
runner, tool, client or effect; a test reads every directive's URI from
Dart's parse tree and holds it to that.
