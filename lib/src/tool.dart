import 'package:checked_json/checked_json.dart';
import 'package:is_tools_api/is_tools_api.dart';

import 'run.dart';

/// A tool's definition with the code that answers its calls.
///
/// Made only by [AnsweredBy.answeredBy], so the code takes the definition's
/// [I] and answers with its [O]: code that returns a `Result<String>` for a
/// `ToolSpec<Args, ExecResult>` does not compile.
final class Tool<I, O> {
  const Tool._(this.spec, this._answer);

  final ToolSpec<I, O> spec;
  final Result<O> Function(I input) _answer;

  /// A call taking [input], followed on [journeyPath] to what the model is
  /// told.
  ///
  /// Here, where [I] and [O] are known, so whoever holds a tool of unknown
  /// types never handles its input or output. An input the definition does
  /// not accept is an error naming the field; nothing is run for it.
  Future<Reply> reply(
    JsonObject input,
    JourneyPath<Object?> journeyPath,
  ) async {
    final I read;
    try {
      read = spec.input.read(input);
    } on JsonFieldException catch (e) {
      return Reply._(e.message, isError: true);
    }
    var result = _answer(read);
    while (true) {
      switch (result) {
        case Done(:final value):
          return Reply._(spec.output.forModel(value), isError: false);
        case Failed(:final why):
          return Reply._(why, isError: true);
        case Run():
          result = await result.next(journeyPath);
      }
    }
  }
}

/// What the model is told of a call: [forModel], as its tool result, marked
/// [isError] when the call failed.
final class Reply {
  const Reply._(this.forModel, {required this.isError});

  final String forModel;
  final bool isError;
}

extension AnsweredBy<I, O> on ToolSpec<I, O> {
  /// This definition, with [answer] answering its calls.
  Tool<I, O> answeredBy(Result<O> Function(I input) answer) =>
      Tool._(this, answer);
}
