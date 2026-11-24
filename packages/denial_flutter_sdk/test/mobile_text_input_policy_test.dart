import 'package:denial_flutter_sdk/src/widgets/mobile_text_input_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds += 1;
    return const SizedBox.shrink();
  }
}

void main() {
  // The shell switches between the tablet (mobile) and desktop
  // presentations. Everything below the policy, the switch's own cover
  // included, keeps its state across a switch.
  testWidgets('switching the policy off and on keeps the state below', (
    tester,
  ) async {
    Widget policy(bool enabled) => MobileTextInputPolicy(
      enabled: enabled,
      child: const _Counter(),
    );
    await tester.pumpWidget(policy(true));
    final state = tester.state<_CounterState>(find.byType(_Counter));
    await tester.pumpWidget(policy(false));
    await tester.pumpWidget(policy(true));
    expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));
  });

  testWidgets('on the tablet a tap outside a field unfocuses it', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Object? handled;
    await tester.pumpWidget(
      MobileTextInputPolicy(
        child: Builder(
          builder: (context) {
            handled = Actions.maybeFind<EditableTextTapOutsideIntent>(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(handled, isNotNull);
    await tester.pumpWidget(
      MobileTextInputPolicy(
        enabled: false,
        child: Builder(
          builder: (context) {
            handled = Actions.maybeFind<EditableTextTapOutsideIntent>(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(handled, isNull);
  });
}
