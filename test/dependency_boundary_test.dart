import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
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
    'package' => uri.pathSegments.first == 'is_effects',
    '' => !uri.isAbsolute && !uri.pathSegments.contains('..'),
    _ => false,
  };
}

void main() {
  test('the contract imports no runner, tool, client or effect', () {
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
      reason: 'is_airlock_api is a contract: it describes runs and carries out none',
    );
  });
}
