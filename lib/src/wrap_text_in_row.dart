import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';

class WrapTextInRow extends DartLintRule {
  const WrapTextInRow()
    : super(
        code: const LintCode(
          name: 'wrap_text_in_row',
          problemMessage:
              'Text widgets inside Row should be wrapped with Flexible or Expanded to prevent overflow.',
          correctionMessage: 'Wrap the Text widget with a Flexible widget.',
          errorSeverity: ErrorSeverity.WARNING,
        ),
      );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addInstanceCreationExpression((node) {
      // Check if this is a Row widget
      final constructorName = node.constructorName.toString();
      if (constructorName != 'Row') return;

      // Find the children property in the Row
      final arguments = node.argumentList.arguments;
      for (final argument in arguments) {
        if (argument is NamedExpression && argument.name.label.name == 'children') {
          // Get the list of children
          final childrenExpr = argument.expression;
          if (childrenExpr is ListLiteral) {
            // Check each child in the list
            for (final child in childrenExpr.elements) {
              if (child is Expression && _isUnwrappedText(child)) {
                reporter.atNode(child, code);
              }
            }
          }
        }
      }
    });
  }

  /// Checks if the node is a Text widget that is not wrapped in Flexible or Expanded
  bool _isUnwrappedText(Expression node) {
    // Direct Text widget
    if (_isTextWidget(node)) {
      return true;
    }

    // Check if it's a wrapped Text but not with Flexible/Expanded
    if (node is InstanceCreationExpression) {
      final constructorName = node.constructorName.toString();

      // If it's already a Flexible or Expanded, it's fine
      if (constructorName == 'Flexible' || constructorName == 'Expanded') {
        return false;
      }

      // Check if this widget contains a Text widget
      final hasTextChild = _containsTextWidget(node);
      if (hasTextChild) {
        return true;
      }
    }

    return false;
  }

  /// Checks if the node is a Text widget
  bool _isTextWidget(Expression node) {
    if (node is InstanceCreationExpression) {
      final constructorName = node.constructorName.toString();
      return constructorName == 'Text' ||
          constructorName == 'RichText' ||
          constructorName == 'SelectableText' ||
          constructorName == 'CustomText';
    }
    return false;
  }

  /// Checks if the widget contains a Text widget as a child or descendant
  bool _containsTextWidget(InstanceCreationExpression node) {
    final arguments = node.argumentList.arguments;

    for (final argument in arguments) {
      // Look for the child property
      if (argument is NamedExpression &&
          (argument.name.label.name == 'child' ||
              argument.name.label.name == 'text')) {
        return _isTextWidget(argument.expression) ||
            (argument.expression is InstanceCreationExpression &&
                _containsTextWidget(
                  argument.expression as InstanceCreationExpression,
                ));
      }
    }

    return false;
  }

  @override
  List<Fix> getFixes() => [WrapWithFlexibleFix()];
}

class WrapWithFlexibleFix extends DartFix {
  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError analysisError,
    List<AnalysisError> others,
  ) {
    context.registry.addInstanceCreationExpression((node) {
      if (!analysisError.sourceRange.intersects(node.sourceRange)) return;

      final changeBuilder = reporter.createChangeBuilder(
        message: 'Wrap with Flexible',
        priority: 1,
      );

      changeBuilder.addDartFileEdit((builder) {
        final nodeText = node.toSource();

        // Create the fix with Flexible wrapping the original widget
        final replacement = 'Flexible(child: $nodeText)';

        builder.addSimpleReplacement(
          SourceRange(node.offset, node.length),
          replacement,
        );
      });
    });
  }
}