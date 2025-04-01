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
        if (argument is NamedExpression &&
            argument.name.label.name == 'children') {
          // Get the list of children
          final childrenExpr = argument.expression;
          if (childrenExpr is ListLiteral) {
            // Check each child in the list
            for (final child in childrenExpr.elements) {
              if (child is Expression) {
                // Handle conditional expressions (ternary)
                if (child is ConditionalExpression) {
                  _checkConditionalExpression(child, reporter);
                }
                // Handle regular widgets
                else if (_isUnwrappedText(child)) {
                  reporter.atNode(child, code);
                }
              }
            }
          }
        }
      }
    });
  }

  /// Checks a conditional expression for unwrapped text widgets
  void _checkConditionalExpression(
    ConditionalExpression conditional,
    ErrorReporter reporter,
  ) {
    // Check both branches of the conditional
    final thenExpr = conditional.thenExpression;
    final elseExpr = conditional.elseExpression;

    // Report issues for either branch that has unwrapped text
    if (_isUnwrappedText(thenExpr)) {
      reporter.atNode(thenExpr, code);
    }

    if (_isUnwrappedText(elseExpr)) {
      reporter.atNode(elseExpr, code);
    }
  }

  /// Checks if the node is a Text widget that is not wrapped in Flexible or Expanded
  bool _isUnwrappedText(Expression node) {
    // Handle conditional expressions recursively
    if (node is ConditionalExpression) {
      return _isUnwrappedText(node.thenExpression) ||
          _isUnwrappedText(node.elseExpression);
    }

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
    // Add handler for conditional expressions (ternary operators)
    context.registry.addConditionalExpression((node) {
      if (!analysisError.sourceRange.intersects(node.sourceRange)) return;
      
      // Find which branch contains the error
      final thenIntersects = analysisError.sourceRange.intersects(node.thenExpression.sourceRange);
      final elseIntersects = analysisError.sourceRange.intersects(node.elseExpression.sourceRange);
      
      if (thenIntersects) {
        _handleExpression(node.thenExpression, reporter, analysisError);
      } else if (elseIntersects) {
        _handleExpression(node.elseExpression, reporter, analysisError);
      }
    });
    
    // Add handler for regular expression nodes (including instance creation)
    context.registry.addInstanceCreationExpression((node) {
      if (!analysisError.sourceRange.intersects(node.sourceRange)) return;
      _handleExpression(node, reporter, analysisError);
    });
  }
  
  // Handle any expression node (might be Text or container)
  void _handleExpression(
    Expression node,
    ChangeReporter reporter,
    AnalysisError analysisError,
  ) {
    // Skip if already wrapped with Flexible
    if (node is InstanceCreationExpression) {
      final constructorName = node.constructorName.toString();
      if (constructorName == 'Flexible' || constructorName == 'Expanded') {
        return;
      }
      
      // Check if this is a Text widget
      if (_isTextWidget(node)) {
        _wrapWithFlexible(node, reporter);
        return;
      }
      
      // Check if it contains a text widget to wrap
      final textNode = _findTextNodeToWrap(node);
      if (textNode != null) {
        _wrapNestedTextWithFlexible(node, textNode, reporter);
      }
    }
  }
  
  // Wrap a direct Text widget with Flexible
  void _wrapWithFlexible(Expression node, ChangeReporter reporter) {
    final changeBuilder = reporter.createChangeBuilder(
      message: 'Wrap with Flexible',
      priority: 1,
    );
    
    changeBuilder.addDartFileEdit((builder) {
      final nodeText = node.toSource();
      final replacement = 'Flexible(child: $nodeText)';
      
      builder.addSimpleReplacement(
        SourceRange(node.offset, node.length),
        replacement,
      );
    });
  }
  
  // Wrap a text widget nested inside a container
  void _wrapNestedTextWithFlexible(
    InstanceCreationExpression container,
    InstanceCreationExpression textNode,
    ChangeReporter reporter,
  ) {
    final changeBuilder = reporter.createChangeBuilder(
      message: 'Wrap with Flexible',
      priority: 1,
    );
    
    changeBuilder.addDartFileEdit((builder) {
      final containerSource = container.toSource();
      final textNodeSource = textNode.toSource();
      
      // Replace just the Text widget with Flexible(child: Text(...))
      final wrappedText = 'Flexible(child: $textNodeSource)';
      final newSource = containerSource.replaceFirst(textNodeSource, wrappedText);
      
      builder.addSimpleReplacement(
        SourceRange(container.offset, container.length),
        newSource,
      );
    });
  }
  
  // Check if this is a Text widget
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
  
  // Find a Text widget nested inside a container
  InstanceCreationExpression? _findTextNodeToWrap(InstanceCreationExpression node) {
    // Check direct child properties first
    for (final argument in node.argumentList.arguments) {
      if (argument is NamedExpression &&
          (argument.name.label.name == 'child' || 
           argument.name.label.name == 'text')) {
        
        if (_isTextWidget(argument.expression)) {
          return argument.expression as InstanceCreationExpression;
        }
        
        if (argument.expression is InstanceCreationExpression) {
          final childExpr = argument.expression as InstanceCreationExpression;
          // Recursively check in container widgets
          final nestedText = _findTextNodeToWrap(childExpr);
          if (nestedText != null) {
            return nestedText;
          }
        }
      }
    }
    
    return null;
  }
}