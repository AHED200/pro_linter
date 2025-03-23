import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/error/error.dart'
    hide
        // ignore: undefined_hidden_name, necessary to support lower analyzer versions
        LintCode;
import 'package:analyzer/error/listener.dart';

/// A plugin class is used to list all the assists/lints defined by a plugin.
class AvoidEmitAfterAwait extends PluginBase {
  /// We list all the custom warnings/infos/errors
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
    _AvoidEmitAfterAwait(),
  ];
}


class _AvoidEmitAfterAwait extends DartLintRule {
  _AvoidEmitAfterAwait()
    : super(
        code: const LintCode(
          name: 'avoid_emit_after_await',
          problemMessage:
              'Avoid emitting state after await without checking if the bloc is closed.',
          correctionMessage: 'Wrap the emit call in an if (!isClosed) check.',
          errorSeverity: ErrorSeverity.ERROR,
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

  void _checkEmitAfterAwait(MethodInvocation node, ErrorReporter reporter) {
    final functionBody = node.thisOrAncestorOfType<FunctionBody>();
    if (functionBody == null || !functionBody.isAsynchronous) return;

    final awaitExpressions = _getAwaitExpressionsInFunction(functionBody);
    if (awaitExpressions.isEmpty) return;

    final hasAwaitBefore = awaitExpressions.any(
      (awaitExpr) => awaitExpr.offset < node.offset,
    );
    if (!hasAwaitBefore) return;

    if (!_isGuardedByIsClosedCheck(node)) {
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

  bool _isGuardedByIsClosedCheck(MethodInvocation node) {
    final ifStatement = node.thisOrAncestorOfType<IfStatement>();
    if (ifStatement == null) return false;

    final condition = ifStatement.expression;
    if (condition is! PrefixExpression || condition.operator != '!')
      return false;

    final operand = condition.operand;
    if (operand is! PropertyAccess) return false;

    final propertyName = operand.propertyName.token.lexeme;
    final target = operand.target;
    return propertyName == 'isClosed' && target is ThisExpression;
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
