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
  AstNode? current = node;

  // 1. First check if we're inside a Future callback
  FunctionExpression? callbackFunction;
  AstNode? searchNode = node;
  while (searchNode != null && callbackFunction == null) {
    if (searchNode is FunctionExpression) {
      final parent = searchNode.parent;
      if (parent is ArgumentList && parent.parent is MethodInvocation) {
        final call = parent.parent as MethodInvocation;
        final name = call.methodName.staticElement?.name;
        if (name == 'then' || name == 'whenComplete' || name == 'catchError') {
          callbackFunction = searchNode;
          break;
        }
      }
    }
    searchNode = searchNode.parent;
  }
  
  // 2. If we're inside a Future callback, we MUST have a guard INSIDE the callback
  if (callbackFunction != null) {
    // Only check inside this callback function's body
    if (callbackFunction.body is BlockFunctionBody) {
      final block = (callbackFunction.body as BlockFunctionBody).block;
      return _hasIsClosedGuard(block, node.offset);
    } else if (callbackFunction.body is ExpressionFunctionBody) {
      final expr = (callbackFunction.body as ExpressionFunctionBody).expression;
      // Check if the expression body has a guard (like a ternary)
      if (expr is ConditionalExpression) {
        final condition = expr.condition.toSource();
        if (condition.contains('!isClosed') || condition.contains('isNotClosed')) {
          return _isNodeInside(node, expr.thenExpression);
        }
      }
      // For arrow functions with && checks
      if (expr is BinaryExpression && expr.operator.type == TokenType.AMPERSAND_AMPERSAND) {
        final left = expr.leftOperand.toSource();
        if (left.contains('!isClosed') || left.contains('isNotClosed')) {
          return true;
        }
      }
      return false;
    }
    return false;
  }

  // 3. For other cases (not in Future callback), proceed with normal checks
  while (current != null) {
    // Case 1: Direct guard with if (!isClosed) { emit(...) }
    if (current is IfStatement) {
      final condition = current.expression.toSource();
      if (condition.contains('!isClosed') ||
          condition.contains('isNotClosed')) {
        if (_isNodeInside(node, current.thenStatement)) {
          return true;
        }
      }
    }

    // Case 2: Early return pattern
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

    // Case 3: Ternary operator
    if (current is ConditionalExpression) {
      final condition = current.condition.toSource();
      if (condition.contains('isClosed')) {
        final isNegated =
            condition.contains('!isClosed') ||
            condition.contains('isNotClosed');
        if (isNegated && _isNodeInside(node, current.thenExpression)) {
          return true;
        } else if (!isNegated &&
            _isNodeInside(node, current.elseExpression)) {
          return true;
        }
      }
    }

    current = current.parent;
  }
  return false;
}
  /// Checks a Block recursively for any if(!isClosed) or early-return isClosed guard.
  bool _hasIsClosedGuard(Block block, int emitOffset) {
    for (final statement in block.statements) {
      // Direct guard
      if (statement is IfStatement) {
        final condition = statement.expression.toSource();
        if (condition.contains('!isClosed') ||
            condition.contains('isNotClosed')) {
          return true;
        }
        if (condition.contains('isClosed') &&
            !condition.contains('!isClosed') &&
            _containsReturnStatement(statement.thenStatement)) {
          return true;
        }
      }

      // If we have nested blocks, visit them too
      if (statement is Block) {
        if (_hasIsClosedGuard(statement, emitOffset)) {
          return true;
        }
      } else if (statement is IfStatement) {
        // Check the if branch
        if (statement.thenStatement is Block) {
          if (_hasIsClosedGuard(statement.thenStatement as Block, emitOffset)) {
            return true;
          }
        }
        // Check the else branch
        if (statement.elseStatement is Block) {
          if (_hasIsClosedGuard(statement.elseStatement as Block, emitOffset)) {
            return true;
          }
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
        // Get the original emit call and its indentation
        final emitCall = node.toSource();

        // Create properly formatted guard with correct indentation
        final replacement =
            'if (!isClosed) {'
            ' $emitCall;'
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
