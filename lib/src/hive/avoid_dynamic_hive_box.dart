import 'package:analyzer/dart/ast/ast.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';

class AvoidDynamicHiveBox extends DartLintRule {
  const AvoidDynamicHiveBox()
    : super(
        code: const LintCode(
          name: 'avoid_dynamic_hive_box',
          problemMessage: 'Avoid creating dynamic Hive boxes without type parameters.',
          correctionMessage:
              'Add a type parameter to the Hive box, e.g., Hive.openBox<MyType>().',
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
      // Check if this is a Hive box opening method
      final boxOpeningMethods = {
        'openBox',
        'openLazyBox',
        'box',
        'lazyBox',
      };

      final methodName = node.methodName.name;
      if (!boxOpeningMethods.contains(methodName)) return;

      // Check if the target is Hive or Hive instance
      final target = node.target;
      if (target == null) return;
      
      if (!_isHiveClass(target)) return;

      // Check if type arguments are missing or dynamic
      if (_hasDynamicOrMissingTypeArg(node)) {
        reporter.atNode( node, code);
      }
    });
  }

  bool _isHiveClass(Expression expression) {
    if (expression is SimpleIdentifier) {
      return expression.name == 'Hive';
    }
    return false;
  }

  bool _hasDynamicOrMissingTypeArg(MethodInvocation node) {
    // No type arguments provided
    if (node.typeArguments == null || node.typeArguments!.arguments.isEmpty) {
      return true;
    }

    // Check if type argument is 'dynamic'
    final typeArg = node.typeArguments!.arguments.first;
    return typeArg.toSource() == 'dynamic';
  }
}