import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:pro_linter/src/bloc/avoid_emit_after_await.dart';
import 'package:pro_linter/src/avoid_print.dart';
import 'package:pro_linter/src/hive/avoid_dynamic_hive_box.dart';
import 'package:pro_linter/src/hive/check_hive_box_open.dart';
import 'package:pro_linter/src/widget/wrap_text_in_row.dart';

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
      const AvoidDynamicHiveBox(),
    ];
  }

  @override
  List<Assist> getAssists() {
    return <Assist>[
      // Your custom assists go here
    ];
  }
}