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

  /// What this tool's code returns for a call taking [input].
  Result<O> call(I input) => _answer(input);
}

extension AnsweredBy<I, O> on ToolSpec<I, O> {
  /// This definition, with [answer] answering its calls.
  Tool<I, O> answeredBy(Result<O> Function(I input) answer) =>
      Tool._(this, answer);
}
