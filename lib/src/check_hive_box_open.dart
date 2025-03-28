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
      
      current = current.parent;
    }
    
    return false;
  }

  bool _isPositiveIsOpenCheck(String condition, String boxSource) {
    return condition.contains('$boxSource.isOpen');
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
      return statement.statements.any((s) => s is ReturnStatement || 
          (s is Block && _containsReturn(s)));
    }
    return false;
  }

  // @override
  // List<Fix> getFixes() => [AddHiveBoxOpenCheck()];
}

// class AddHiveBoxOpenCheck extends DartFix {
//   @override
//   void run(
//     CustomLintResolver resolver,
//     ChangeReporter reporter,
//     CustomLintContext context,
//     AnalysisError analysisError,
//     List<AnalysisError> others,
//   ) {
//     context.registry.addMethodInvocation((node) {
//       if (!analysisError.sourceRange.intersects(node.sourceRange)) return;
      
//       final changeBuilder = reporter.createChangeBuilder(
//         message: 'Add box.isOpen check',
//         priority: 1,
//       );
      
//       changeBuilder.addDartFileEdit((builder) {
//         final target = node.target;
//         if (target == null) return;
        
//         final boxName = target.toSource();
//         final operationCall = node.toSource();
        
//         // Get source code to determine indentation
//         final source = node.root.toSource();
//         final lineStart = source.lastIndexOf('\n', node.offset);
//         final indentation = lineStart == -1 
//             ? '' 
//             : source.substring(lineStart + 1, node.offset).replaceAll(RegExp(r'[^\s]'), '');
        
//         // Check if we're inside a Future callback
//         bool isInFutureCallback = _isInsideFutureCallback(node);
        
//         // Find the statement that contains this method call
//         AstNode? currentStatement = node;
//         while (currentStatement != null && 
//                !(currentStatement is Statement || 
//                  currentStatement is ExpressionStatement)) {
//           currentStatement = currentStatement.parent;
//         }
        
//         // Case 1: Inside a complex expression (like in the middle of a chain)
//         if (currentStatement == null || 
//             (currentStatement is! ExpressionStatement && 
//              currentStatement is! Statement)) {
//           // Compact inline format (for expressions)
//           final replacement = '$boxName.isOpen ? $operationCall : null';
//           builder.addSimpleReplacement(
//             SourceRange(node.offset, node.length),
//             replacement,
//           );
//         }
//         // Case 2: Inside a Future callback
//         else if (isInFutureCallback) {
//           // Inline format for Future callbacks to avoid breaking structure
//           final replacement = 'if ($boxName.isOpen) {\n'
//               '$indentation  $operationCall\n'
//               '$indentation}';
//           builder.addSimpleReplacement(
//             SourceRange(node.offset, node.length),
//             replacement,
//           );
//         }
//         // Case 3: Normal standalone statement
//         else {
//           // We can wrap the entire line with proper formatting
//           final replacement = 'if ($boxName.isOpen) {\n'
//               '$indentation  $operationCall\n'
//               '$indentation}';
          
//           builder.addSimpleReplacement(
//             SourceRange(node.offset, node.length),
//             replacement,
//           );
//         }
//       });
//     });
//   }
  
//   bool _isInsideFutureCallback(AstNode node) {
//     AstNode? current = node;
//     while (current != null) {
//       // Check if we're in a function expression (like an arrow function or lambda)
//       if (current is FunctionExpression) {
//         // Check if the function is an argument to a Future method
//         final parent = current.parent;
//         if (parent is ArgumentList && parent.parent is MethodInvocation) {
//           final methodCall = parent.parent as MethodInvocation;
//           final methodName = methodCall.methodName.name;
//           // Common Future callback methods
//           if (methodName == 'then' || 
//               methodName == 'whenComplete' || 
//               methodName == 'catchError' ||
//               methodName == 'onError') {
//             return true;
//           }
//         }
//       }
//       current = current.parent;
//     }
//     return false;
//   }
// }