import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/error/error.dart'
    hide
        // ignore: undefined_hidden_name, necessary to support lower analyzer versions
        LintCode;
import 'package:analyzer/error/listener.dart';

class AvoidEmitAfterAwait extends DartLintRule {
  const AvoidEmitAfterAwait()
    : super(
        code: const LintCode(
          name: 'avoid_emit_after_await',
          problemMessage:
              'Avoid emitting state after await without checking if the bloc is closed.',
          correctionMessage: 'Wrap the emit call in an if (!isClosed) check.',
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
      if (node.methodName.name == 'emit') {
        _checkEmitAfterAwait(node, reporter);
      }
    });
  }

  bool _isNodeInside(AstNode node, AstNode container) {
    return container.offset <= node.offset && node.end <= container.end;
  }

  void _checkEmitAfterAwait(MethodInvocation node, ErrorReporter reporter) {
    // 1. Find the nearest enclosing asynchronous function body
    FunctionBody? asyncFunctionBody;
    AstNode? current = node;
    while (current != null) {
      if (current is FunctionBody && current.isAsynchronous) {
        asyncFunctionBody = current;
        break;
      }
      current = current.parent;
    }
    if (asyncFunctionBody == null) return;

    // 2. Get all await expressions in this async function
    final awaitExpressions = _getAwaitExpressionsInFunction(asyncFunctionBody);
    if (awaitExpressions.isEmpty) return;

    // 3. Check if any await comes before the emit call
    final hasAwaitBefore = awaitExpressions.any(
      (awaitExpr) => awaitExpr.offset < node.offset,
    );

    if (!hasAwaitBefore) return;

    // 4. Report if not guarded by isClosed check
    if (!_isGuardedByIsClosed(node)) {
      reporter.atNode(node, code);
    }
  }

  List<AwaitExpression> _getAwaitExpressionsInFunction(
    FunctionBody functionBody,
  ) {
    final awaitExpressions = <AwaitExpression>[];
    functionBody.visitChildren(AwaitVisitor(awaitExpressions));
    return awaitExpressions;
  }

  /// Traverse up the AST to check if the node is wrapped in an if-statement that
  /// guards the call with a check like `if (!isClosed)` or equivalent.
  bool _isGuardedByIsClosed(AstNode node) {
    // First, check if the emit is directly guarded by an if-statement
    AstNode? current = node;
    while (current != null) {
      if (current is IfStatement) {
        final condition = current.expression.toSource();
        if ((condition.contains('!isClosed') ||
                condition.contains('isNotClosed')) &&
            _isNodeInside(node, current.thenStatement)) {
          return true;
        }
      }

      // Handle early return pattern
      if (current is Block) {
        for (final statement in current.statements) {
          if (statement.offset >= node.offset) break;

          if (statement is IfStatement) {
            final condition = statement.expression.toSource();
            if (condition.contains('isClosed') &&
                !condition.contains('!isClosed')) {
              if (_containsReturnStatement(statement.thenStatement)) {
                return true;
              }
            }
          }
        }
      }

      current = current.parent;
    }

    // If not found, trace up to find the containing function
    // This handles not just direct then() callbacks but any nested function
    FunctionExpression? containingFunction = _findContainingFunction(node);
    if (containingFunction != null) {
      // Found a function - see if the node is inside a guard within this function
      if (containingFunction.body is BlockFunctionBody) {
        final block = (containingFunction.body as BlockFunctionBody).block;
        return _hasIsClosedGuardInBlock(block, node);
      } else if (containingFunction.body is ExpressionFunctionBody) {
        final expr =
            (containingFunction.body as ExpressionFunctionBody).expression;

        // Handle arrow function with conditional
        if (expr is ConditionalExpression) {
          final condition = expr.condition.toSource();
          if (condition.contains('!isClosed') ||
              condition.contains('isNotClosed')) {
            return _isNodeInside(node, expr.thenExpression);
          }
        }

        // Handle arrow function with && guard
        if (expr is BinaryExpression &&
            expr.operator.type == TokenType.AMPERSAND_AMPERSAND) {
          final left = expr.leftOperand.toSource();
          if (left.contains('!isClosed') || left.contains('isNotClosed')) {
            return true;
          }
        }

        // Handle nested functions in arrow expressions
        if (expr is MethodInvocation) {
          return _checkNestedMethodForGuard(expr, node);
        }
      }
    }

    return false;
  }

  // Helper to find the immediate containing function
  FunctionExpression? _findContainingFunction(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      if (current is FunctionExpression) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  // Comprehensive check for guards in a block that might contain the emit
  bool _hasIsClosedGuardInBlock(Block block, AstNode emitNode) {
    // Check for direct if-statements guarding the emit
    for (final statement in block.statements) {
      if (statement is IfStatement) {
        final condition = statement.expression.toSource();
        if ((condition.contains('!isClosed') ||
                condition.contains('isNotClosed')) &&
            _isNodeInside(emitNode, statement.thenStatement)) {
          return true;
        }
      }

      // Check for early return pattern
      if (statement.offset < emitNode.offset && statement is IfStatement) {
        final condition = statement.expression.toSource();
        if (condition.contains('isClosed') &&
            !condition.contains('!isClosed')) {
          if (_containsReturnStatement(statement.thenStatement)) {
            return true;
          }
        }
      }

      // Check nested blocks
      if (statement is Block) {
        if (_hasIsClosedGuardInBlock(statement, emitNode)) {
          return true;
        }
      }

      // Check method calls that might contain functions
      if (statement is ExpressionStatement &&
          statement.expression is MethodInvocation) {
        final methodCall = statement.expression as MethodInvocation;
        if (_checkNestedMethodForGuard(methodCall, emitNode)) {
          return true;
        }
      }
    }

    return false;
  }

  // Helper to check a method call for guards in its function arguments
  bool _checkNestedMethodForGuard(
    MethodInvocation methodCall,
    AstNode emitNode,
  ) {
    // Check each argument for function expressions
    for (final arg in methodCall.argumentList.arguments) {
      if (arg is FunctionExpression) {
        if (arg.body is BlockFunctionBody) {
          final block = (arg.body as BlockFunctionBody).block;
          if (_hasIsClosedGuardInBlock(block, emitNode)) {
            return true;
          }
        } else if (arg.body is ExpressionFunctionBody) {
          final expr = (arg.body as ExpressionFunctionBody).expression;

          // If the expression is a method call (like fold)
          if (expr is MethodInvocation) {
            if (_checkNestedMethodForGuard(expr, emitNode)) {
              return true;
            }
          }

          // Handle conditional and binary expressions
          if (expr is ConditionalExpression) {
            final condition = expr.condition.toSource();
            if ((condition.contains('!isClosed') ||
                    condition.contains('isNotClosed')) &&
                _isNodeInside(emitNode, expr.thenExpression)) {
              return true;
            }
          }
          if (expr is BinaryExpression &&
              expr.operator.type == TokenType.AMPERSAND_AMPERSAND) {
            final left = expr.leftOperand.toSource();
            if (left.contains('!isClosed') || left.contains('isNotClosed')) {
              return true;
            }
          }
        }
      } else if (arg is NamedExpression &&
          arg.expression is FunctionExpression) {
        // Handle named arguments
        final func = arg.expression as FunctionExpression;
        if (func.body is BlockFunctionBody) {
          final block = (func.body as BlockFunctionBody).block;
          if (_hasIsClosedGuardInBlock(block, emitNode)) {
            return true;
          }
        }
      } else if (arg is MethodInvocation) {
        // Recurse for nested method calls
        if (_checkNestedMethodForGuard(arg, emitNode)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Helper to check if a statement contains a return
  bool _containsReturnStatement(Statement statement) {
    if (statement is ReturnStatement) return true;
    if (statement is Block) {
      for (final stmt in statement.statements) {
        if (stmt is ReturnStatement) return true;
      }
    }
    return false;
  }

  @override
  List<Fix> getFixes() => [AddCheckBox()];
}

class AddCheckBox extends DartFix {
  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError analysisError,
    List<AnalysisError> others,
  ) {
    // Find the method invocation node that caused the lint
    context.registry.addMethodInvocation((node) {
      if (!analysisError.sourceRange.intersects(node.sourceRange)) return;

      // Make sure this is an emit statement
      if (node.methodName.name != 'emit') return;

      // Create a builder for the fix
      final changeBuilder = reporter.createChangeBuilder(
        message: 'Add if (!isClosed) guard',
        priority: 1,
      );

      // Apply the fix
      changeBuilder.addDartFileEdit((builder) {
        final statement = node.thisOrAncestorOfType<ExpressionStatement>();
        if (statement == null) return;

        final originalCode = statement.toSource();

        // Create properly formatted guard with correct indentation
        final replacement =
            'if (!isClosed) {\n'
            ' $originalCode\n'
            '}';

        builder.addSimpleReplacement(
          SourceRange(node.offset, node.length),
          replacement,
        );
      });
    });
  }
}

class AwaitVisitor extends RecursiveAstVisitor<void> {
  final List<AwaitExpression> awaitExpressions;

  AwaitVisitor(this.awaitExpressions);

  @override
  void visitAwaitExpression(AwaitExpression node) {
    awaitExpressions.add(node);
    super.visitAwaitExpression(node);
  }
}
