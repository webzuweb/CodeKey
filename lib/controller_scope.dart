import 'package:flutter/widgets.dart';

import 'app_controller.dart';

class CodeKeyScope extends InheritedNotifier<CodeKeyController> {
  const CodeKeyScope({
    super.key,
    required CodeKeyController controller,
    required super.child,
  }) : super(notifier: controller);

  static CodeKeyController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CodeKeyScope>();
    assert(scope != null, 'CodeKeyScope not found');
    return scope!.notifier!;
  }

  static CodeKeyController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<CodeKeyScope>();
    final scope = element?.widget as CodeKeyScope?;
    assert(scope != null, 'CodeKeyScope not found');
    return scope!.notifier!;
  }
}
