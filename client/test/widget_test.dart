import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/models_ui.dart';
import 'package:client/widgets/mode_switch.dart';

void main() {
  test('wire risk values map to the expected UI levels', () {
    expect(riskFromString('SAFE'), RiskLevel.safe);
    expect(riskFromString('DANGEROUS'), RiskLevel.dangerous);
    expect(riskFromString('BLOCKED_BY_WORKSPACE'), RiskLevel.blockedByWorkspace);
  });

  testWidgets('Plan/Build switch reports the selected mode', (WidgetTester tester) async {
    AgentMode? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModeSwitch(
            mode: AgentMode.plan,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);

    await tester.tap(find.text('Build'));
    await tester.pump();
    expect(selected, AgentMode.build);
  });
}
