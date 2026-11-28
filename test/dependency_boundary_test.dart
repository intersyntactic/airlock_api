import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Every URI a source's directives name, in every branch, as written.
///
/// Read from the parse tree, which knows comments, strings and metadata, so
/// none of them can hide a directive or cut one short. The tree keeps every
/// branch of a conditional import (the element model keeps only the one it
/// picked), and `import 'stub.dart' if (dart.library.io) 'dart:io';` names
/// both.
Iterable<StringLiteral> directiveUris(String source) sync* {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  // Over every directive, unfiltered and exhaustive, so a new kind of
  // directive stops this compiling.
  for (final directive in unit.directives) {
    yield* switch (directive) {
      NamespaceDirective(:final uri, :final configurations) => [
        uri,
        for (final branch in configurations) branch.uri,
      ],
      PartDirective(:final uri) => [uri],
      LibraryDirective() || PartOfDirective() => const <StringLiteral>[],
    };
  }
}

const _allowedSdk = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};

bool _allowed(String target) {
  final uri = Uri.parse(target);
  return switch (uri.scheme) {
    'dart' => _allowedSdk.contains(target),
    'package' => const {
      'checked_json',
      'is_content_id',
      'is_conversation_vocabulary',
      'is_file_request_vocabulary',
      'is_model_vocabulary',
      'is_outcome_vocabulary',
      'is_program_request_vocabulary',
      'is_relative_path_vocabulary',
      'is_shapes',
      'is_sign_in_vocabulary',
      'is_web_address_vocabulary',
      'is_web_request_vocabulary',
    }.contains(uri.pathSegments.first),
    '' => !uri.isAbsolute && !uri.pathSegments.contains('..'),
    _ => false,
  };
}

/// Every function body in [source] that is `async` or `async*`.
Iterable<FunctionBody> asyncBodies(String source) {
  final bodies = <FunctionBody>[];
  parseString(
    content: source,
    throwIfDiagnostics: false,
  ).unit.accept(_AsyncBodies(bodies));
  return bodies;
}

final class _AsyncBodies extends RecursiveAstVisitor<void> {
  _AsyncBodies(this.found);

  final List<FunctionBody> found;

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    if (node.isAsynchronous) found.add(node);
    super.visitBlockFunctionBody(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (node.isAsynchronous) found.add(node);
    super.visitExpressionFunctionBody(node);
  }
}

void main() {
  test('the contract carries nothing out: no function in it is async', () {
    final violations = <String>[
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart'))
          for (final body in asyncBodies(file.readAsStringSync()))
            '${file.path}: ${body.parent?.toSource().split('\n').first}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'waiting on something is carrying an action out, which is the '
          "airlock's or the agent loop's, not the contract's",
    );
  });

  test('the contract imports no runner, tool, client or driver', () {
    final violations = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final literal in directiveUris(file.readAsStringSync())) {
        // Null when the URI is not one plain string, so cannot be checked.
        final target = literal.stringValue;
        if (target == null || !_allowed(target)) {
          violations.add('${file.path}: ${target ?? literal.toSource()}');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'is_airlock_api is a contract: it describes actions and reaches no driver',
    );
  });
}
