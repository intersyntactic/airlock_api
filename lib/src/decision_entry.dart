part of 'action.dart';

// An AirlockDecisionOnAction as the logbook holds it, for every reach, so
// the airlock can read back from history which places it decided and which
// decisions have no result after them. Its reach is written as the program
// and input that make it, exactly as a proposal writes them, and read back
// through the same codecs.

/// [reach] as the program and input that make it.
Object? _reachToJson(Reach reach) {
  Object? as<I>(Program<I, Object?> program, I input) => {
    ...program._wire.program,
    'input': program._wire.inputToJson(input),
  };
  return switch (reach) {
    Reads(:final path, as: ReadsAs.text) => as(Program.read, path),
    Reads(:final path, as: ReadsAs.bytes) => as(Program.readBytes, path),
    Writes(:final file) => as(Program.write, file),
    Starts(:final program, :final args) => as(Executable(program), args),
    MakesWebRequest(:final request) => as(Program.web, request),
    CallsTheModel(:final call) => as(Program.askTheModel, call),
  };
}

/// [json] read back as the reach [_reachToJson] wrote. Throws a
/// [FormatException] naming the part, from [field].
Reach _reachFromJson(JsonObject json, String field) {
  final name = json.string('program');
  final program =
      _programNamed(name, json.raw('executable')) ??
      (throw FormatException('$field.program: not a program: $name'));
  return program._work(json.raw('input'), '$field.input').reach;
}

Object? _decisionToJson(Decision decision) => {
  ...switch (decision) {
    Allow(:final by) => {'allow': true, 'by': by.name},
    Deny(:final why, :final by) => {'allow': false, 'why': why, 'by': by.name},
  },
  // Absent when empty, so a decision kept before it existed reads back to
  // the same bytes.
  if (decision.reliedOn.isNotEmpty)
    'reliedOn': [for (final e in decision.reliedOn) e.hex],
};

EntryId? _proposedFromJson(JsonObject json, String field) =>
    switch (json.stringOrNull('proposed')) {
      null => null,
      final hex =>
        EntryId.parse(hex) ??
            (throw FormatException('$field.proposed: not an entry id')),
    };
