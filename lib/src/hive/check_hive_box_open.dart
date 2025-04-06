import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';

class CheckHiveBoxIsOpen extends DartLintRule {
  const CheckHiveBoxIsOpen()
    : super(
        code: const LintCode(
          name: 'check_hive_box_is_open',
          problemMessage: 'Check if the Hive box is open before modifying it.',
          correctionMessage:
              'Add a check like `if (box.isOpen) { ... }` or `if (!box.isOpen) return;` before the operation.',
          errorSeverity: ErrorSeverity.WARNING,
        ),
      );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((node) {
      const modifyingMethods = {
        'put',
        'putAll',
        'delete',
        'deleteAll',
        'add',
        'addAll',
        'clear',
      };

      // Check if method is a Hive box modifier
      final methodName = node.methodName.name;
      if (!modifyingMethods.contains(methodName)) return;

      // Verify receiver is a Hive Box
      final receiver = node.target;
      if (receiver == null) return;
      if (!_isHiveBox(receiver.staticType)) return;

      // Check for guarding conditions
      if (!_hasOpenCheck(node, receiver)) {
        reporter.atNode(node, code);
      }
    });
  }

  bool _isHiveBox(DartType? type) {
    if (type == null) return false;

    // Get the type as a string for easier checking
    final typeStr = type.toString();

    // Check for common Hive box types
    return typeStr.contains('Box<') ||
        typeStr.contains('LazyBox<') ||
        typeStr == 'Box' ||
        typeStr == 'LazyBox' ||
        // Check for Hive package path
        (typeStr.contains('hive') &&
            (typeStr.contains('Box') || typeStr.contains('box')));
  }

  bool _hasOpenCheck(MethodInvocation call, Expression boxExpression) {
    // Get the source representation of the box expression (e.g., "myBox", "this.box")
    final boxSource = boxExpression.toSource();

    // Check if inside an if-statement with isOpen check
    AstNode? current = call;
    while (current != null) {
      // Case 1: Direct guard - if (box.isOpen) { ... }
      if (current is IfStatement) {
        final condition = current.expression.toSource();
        if (_isPositiveIsOpenCheck(condition, boxSource) &&
            _isNodeInside(call, current.thenStatement)) {
          return true;
        }
      }

      // Case 2: Early return - if (!box.isOpen) return;
      if (current is Block) {
        for (final statement in current.statements) {
          if (statement.offset >= call.offset) break;

          if (statement is IfStatement) {
            final condition = statement.expression.toSource();
            if (_isNegativeIsOpenCheck(condition, boxSource) &&
                _containsReturn(statement.thenStatement)) {
              return true;
            }
          }
        }
      }

      // Case 3: Ternary operator - box.isOpen ? ... : ...;
      if (current is ConditionalExpression) {
        final condition = current.condition.toSource();
        if (_isPositiveIsOpenCheck(condition, boxSource)) {
          if (_isNodeInside(call, current.thenExpression)) {
            return true;
          }
        } else if (_isNegativeIsOpenCheck(condition, boxSource)) {
          if (_isNodeInside(call, current.elseExpression)) {
            return true;
          }
        }
      }

      current = current.parent;
    }

    return false;
  }

  bool _isPositiveIsOpenCheck(String condition, String boxSource) {
    return condition.contains('$boxSource.isOpen') ||
        condition.contains('$boxSource?.isOpen');
  }

  bool _isNegativeIsOpenCheck(String condition, String boxSource) {
    return condition.contains('!$boxSource.isOpen') ||
        condition.contains('$boxSource.isClosed');
  }

  bool _isNodeInside(AstNode node, AstNode container) {
    return container.offset <= node.offset && node.end <= container.end;
  }

  bool _containsReturn(Statement statement) {
    if (statement is ReturnStatement) return true;
    if (statement is Block) {
      return statement.statements.any(
        (s) => s is ReturnStatement || (s is Block && _containsReturn(s)),
      );
    }
    return false;
  }

  @override
  List<Fix> getFixes() => [AddTernaryOpenCheck(), AddHiveBoxOpenCheck()];
}

class AddTernaryOpenCheck extends DartFix {
  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError analysisError,
    List<AnalysisError> others,
  ) {
    // Look for the Hive box modifying method invocation that triggered the lint.
    context.registry.addMethodInvocation((node) {
      if (!analysisError.sourceRange.intersects(node.sourceRange)) return;

      // Check that the method is one of the modifying methods.
      const modifyingMethods = {
        'put',
        'putAll',
        'delete',
        'deleteAll',
        'add',
        'addAll',
        'clear',
      };

      if (!modifyingMethods.contains(node.methodName.name)) return;

      // Ensure that we have a receiver for the method invocation.
      final receiver = node.target;
      if (receiver == null) return;

      // Create a change builder for the quick fix.
      final changeBuilder = reporter.createChangeBuilder(
        message: 'Wrap Hive box operation with (isClosed? null : operation)',
        priority: 1,
      );

      changeBuilder.addDartFileEdit((builder) {
        final statement = node.thisOrAncestorOfType<ExpressionStatement>();
        if (statement == null) return;

        final receiverSource = receiver.toSource();
        final originalCode = statement.toSource();

        // Check if using null-safe operator
        final usesNullSafe = node.operator?.type == TokenType.QUESTION_PERIOD;

        // Create appropriate isOpen check based on null-safety
        String isOpenCheck;
        if (usesNullSafe) {
          // For null-safe operations, add null check to isOpen as well
          isOpenCheck = '($receiverSource?.isOpen ?? false)';
        } else {
          // For regular operations, use simple isOpen check
          isOpenCheck = '$receiverSource.isOpen';
        }

        // Build replacement with proper indentation
        final replacement = '$isOpenCheck ? $originalCode : null;';

        builder.addSimpleReplacement(
          SourceRange(statement.offset, statement.length),
          replacement,
        );
      });
    });
  }
}
class AddHiveBoxOpenCheck extends DartFix {
  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError analysisError,
    List<AnalysisError> others,
  ) {
    // Look for the Hive box modifying method invocation that triggered the lint.
    context.registry.addMethodInvocation((node) {
      if (!analysisError.sourceRange.intersects(node.sourceRange)) return;

      // Check that the method is one of the modifying methods.
      const modifyingMethods = {
        'put',
        'putAll',
        'delete',
        'deleteAll',
        'add',
        'addAll',
        'clear',
      };

      if (!modifyingMethods.contains(node.methodName.name)) return;

      // Ensure that we have a receiver for the method invocation.
      final receiver = node.target;
      if (receiver == null) return;

      // Create a change builder for the quick fix.
      final changeBuilder = reporter.createChangeBuilder(
        message: 'Wrap Hive box operation with isOpen check',
        priority: 1,
      );

      changeBuilder.addDartFileEdit((builder) {
        final statement = node.thisOrAncestorOfType<ExpressionStatement>();
        if (statement == null) return;

        final receiverSource = receiver.toSource();
        final originalCode = statement.toSource();

        // Get the source code to determine indentation
        final source = node.root.toSource();
        final lineStart = source.lastIndexOf('\n', statement.offset);
        final indentation =
            lineStart == -1
                ? ''
                : source
                    .substring(lineStart + 1, statement.offset)
                    .replaceAll(RegExp(r'[^\s]'), '');

        // Check if using null-safe operator
        final usesNullSafe = node.operator?.type == TokenType.QUESTION_PERIOD;

        // Create appropriate isOpen check based on null-safety
        String isOpenCheck;
        if (usesNullSafe) {
          // For null-safe operations, add null check to isOpen as well
          isOpenCheck = '($receiverSource?.isOpen ?? false)';
        } else {
          // For regular operations, use simple isOpen check
          isOpenCheck = '$receiverSource.isOpen';
        }

        // Build replacement with proper indentation
        final replacement =
            'if $isOpenCheck {\n'
            '$indentation  $originalCode\n'
            '$indentation}';

        builder.addSimpleReplacement(
          SourceRange(statement.offset, statement.length),
          replacement,
        );
      });
    });
  }
}
