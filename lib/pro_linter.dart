import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:pro_linter/src/avoid_emit_after_await.dart';
import 'package:pro_linter/src/avoid_print.dart';
import 'package:pro_linter/src/check_hive_box_open.dart';
import 'package:pro_linter/src/wrap_text_in_row.dart';

PluginBase createPlugin() => _ProLinter();

class _ProLinter extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) {
    return <LintRule>[
      // Your custom lint rules go here
      const AvoidPrint(),
      const AvoidEmitAfterAwait(),
      const CheckHiveBoxIsOpen(),
      const WrapTextInRow(),
    ];
  }

  @override
  List<Assist> getAssists() {
    return <Assist>[
      // Your custom assists go here
    ];
  }
}