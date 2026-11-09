/// The airlock's contract: what a tool's code returns for a call, the runs
/// of programs it describes, the [Airlock] that decides and records each
/// run, and the way that code is attached to a tool's definition.
///
/// The airlock itself, which decides and records, is not here: this library
/// holds only the types it and the tools agree on.
library;

export 'src/run.dart';
export 'src/tool.dart';
