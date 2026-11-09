# is_airlock_api

The airlock's contract. Tools describe effects; the airlock decides and
records each one; drivers operate the world. A tool's code touches nothing:
for each call it returns a `Result` the airlock follows.

```dart
const dart = Executable('dart');

final writeAndFormat = ToolSpec<FileText, ExecResult>(
  name: 'write_and_format',
  description: 'Writes a Dart file, then formats it.',
  input: Input.fields2(
    Field('path', Schema.string()),
    Field('text', Schema.string()),
    FileText.new,
  ),
  output: ExecResult.output,
).answeredBy(
  (file) => Program.write.runOrRefusal(
    file,
    then: (wrote) =>
        dart.runOrRefusal(Args(['format', file.path]), then: Done.new),
  ),
);
```

- `Result<A>`: what a tool's code returns for a call, where `A` is the tool's
  output type. `Run` (do this, then hand what happened to the continuation),
  `Done(value)` (the answer, rendered for the model by the definition's
  `Output`), or `Failed(why)` (it couldn't; the model is told `why` as an
  error). `Failed` is a `Result<Never>`, so one `Failed` fits every tool.
- `answeredBy`: attaches code to an `is_tools_api` `ToolSpec<I, O>`, giving a
  `Tool<I, O>`. The code must take the definition's `I` and answer with its
  `O`, or it does not compile.
- `Run<A>`: a program, its input, and the continuation. Made only by its
  program (`Program.run`, `Program.runOrRefusal`), so its input is the
  program's own type; typed outside only by the answer it leads to, so a
  switch over a `Result` covers every run with `case Run()`.
- `Run.next(home, airlock)`: the only way to carry out a run. The `Airlock`
  decides it (`Allow` or `Deny(why)`); an allowed run is handed to its
  program with a `Cleared`, which only `next` can make; the airlock records
  the outcome, a refusal included; then the continuation gets it. A `Home`'s
  drivers are reached only through `Cleared`, so holding a home carries out
  nothing.
- `Airlock`: `decide` and `record`, implemented by intersyntactic's airlock.
- `Program<I, O>`: open, so anyone may define one. Here are `ReadFile`
  (`Program.read`), `WriteFile` (`Program.write`) and `Executable('git')`,
  which takes plain `Args`.
- `Outcome<O>`: `Ran(output)` or `Refused(why)`. `Refused` is an
  `Outcome<Never>`, so a switch over the two is exhaustive.
- `ExecResult`: what a started process did, and `ExecResult.output` to render
  it. One that never started is `Refused`, not an `ExecResult`.

The loop that follows a call's result to its answer is the airlock's, not
this package's.

The library imports `is_tools_api` and nothing else; a test reads every
directive's URI from Dart's parse tree and holds it to that.
