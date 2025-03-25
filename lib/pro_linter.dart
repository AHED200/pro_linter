import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:pro_linter/src/avoid_emit_after_await.dart';
import 'package:pro_linter/src/avoid_print.dart';

PluginBase createPlugin() => _ProLinter();

class _ProLinter extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) {
    return <LintRule>[
      // Your custom lint rules go here
      const AvoidPrint(),
      const AvoidEmitAfterAwait(),
    ];
  }

  @override
  List<Assist> getAssists() {
    return <Assist>[
      // Your custom assists go here
    ];
  }
}