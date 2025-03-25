import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/error/error.dart' hide LintCode;

class AvoidPrint extends DartLintRule {
  const AvoidPrint()
    : super(
        code: const LintCode(
          name: 'avoid_print_in_production',
          problemMessage: 'Avoid using print statements in production code.',
          correctionMessage: 'Consider using a logger instead.',
          errorSeverity: ErrorSeverity.WARNING,
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

  @override
  List<Fix> getFixes() {
    return <Fix>[UseLoggerFix()];
  }
}

class UseLoggerFix extends DartFix {
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

      // Make sure this is a print statement
      final Element? element = node.methodName.staticElement;
      if (element?.name != 'print') return;

      // Create a builder for the fix
      final changeBuilder = reporter.createChangeBuilder(
        message: 'Replace with logger.i',
        priority: 1,
      );

      // Apply the fix
      changeBuilder.addDartFileEdit((builder) {
        // Replace the method name
        builder.addSimpleReplacement(
          SourceRange(node.methodName.offset, node.methodName.length),
          'logger.i',
        );
      });
    });
  }
}
