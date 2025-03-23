import 'package:analyzer/dart/ast/ast.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/dart/element/element.dart';

class AvoidPrint extends DartLintRule {
  const AvoidPrint()
    : super(
        code: const LintCode(
          name: 'avoid_print',
          problemMessage: 'Avoid using print statements in production code.',
          correctionMessage: 'Consider using a logger instead.',
          errorSeverity: ErrorSeverity.WARNING,
          url: 'https://doc.my-lint-rules.com/lints/avoid_print',
        ),
      );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    // Register a callback for each method invocation in the file.
    context.registry.addMethodInvocation((MethodInvocation node) {
      // We get the static element of the method name node.
      final Element? element = node.methodName.staticElement;

      print(
        'element: $element, '
        'element.name: ${element?.name}, '
        'element.library: ${element?.library}, '
        'element.library.isDartCore: ${element?.library?.isDartCore}, ',
      );

      // Check if the method's element is a FunctionElement.
      // if (element is! FunctionElement) return;

      // Check if the method name is 'print'.
      if (element?.name != 'print') return;

      // Check if the method's library is 'dart:core'.
      // if (!element.library.isDartCore) return;

      // Report the lint error for the method invocation node.
      reporter.atNode(node, code);
    });
  }
}
