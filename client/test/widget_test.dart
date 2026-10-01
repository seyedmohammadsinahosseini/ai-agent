import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/api_client.dart';
import 'package:client/chat_message.dart';
import 'package:client/models_ui.dart';
import 'package:client/widgets/mode_switch.dart';

void main() {
  test('wire risk values map to the expected UI levels', () {
    expect(riskFromString('SAFE'), RiskLevel.safe);
    expect(riskFromString('DANGEROUS'), RiskLevel.dangerous);
    expect(riskFromString('BLOCKED_BY_WORKSPACE'), RiskLevel.blockedByWorkspace);
  });

  test('pending confirmation survives chat history reload', () {
    final history = ChatHistoryMessage(
      id: 'message-1',
      role: 'assistant',
      content: 'Ready to create the files.',
      createdAt: 'now',
      mode: 'build',
      workingDir: r'C:\workspace',
      suggestedCommand: SuggestedCommand(command: 'Set-Content index.html ok', explanation: 'Create the page'),
      riskLevel: 'CONFIRM',
    );

    final item = ChatMessageItem.fromHistory(history);
    expect(item.pendingConfirmation, isTrue);
    expect(item.workingDir, r'C:\workspace');
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
