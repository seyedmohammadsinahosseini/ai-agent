import 'api_client.dart';
import 'models_ui.dart';

class ChatAttachmentBadge {
  final String filename;
  final String kind; // 'context' | 'workspace'
  ChatAttachmentBadge({required this.filename, required this.kind});
}

class ChatMessageItem {
  final bool isUser;
  final String text;
  final String? mode; // mode active when this message was sent/answered
  final String? historyMessageId; // server id used to persist streamed execution output
  final String? workingDir; // workspace in force when this command was proposed
  final SuggestedCommand? suggestedCommand;
  RiskLevel? riskLevel;
  String? riskReason;
  String? output;
  int? exitCode;
  bool pendingConfirmation;
  bool blocked;
  String? blockedReason;
  bool isStreaming;
  bool wasStopped;
  final bool isError;
  final List<ChatAttachmentBadge> attachments;

  ChatMessageItem({
    required this.isUser,
    required this.text,
    this.mode,
    this.historyMessageId,
    this.workingDir,
    this.suggestedCommand,
    this.riskLevel,
    this.riskReason,
    this.output,
    this.exitCode,
    this.pendingConfirmation = false,
    this.blocked = false,
    this.blockedReason,
    this.isStreaming = false,
    this.wasStopped = false,
    this.isError = false,
    this.attachments = const [],
  });

  /// Rebuilds a message bubble from a previously-saved chat history entry
  /// (see ApiClient.getChat), so reopening a past conversation from the
  /// sidebar looks the same as it did live.
  factory ChatMessageItem.fromHistory(ChatHistoryMessage m) {
    final risk = m.riskLevel != null ? riskFromString(m.riskLevel) : null;
    return ChatMessageItem(
      isUser: m.role == 'user',
      text: m.content,
      mode: m.mode,
      historyMessageId: m.id,
      suggestedCommand: m.suggestedCommand,
      riskLevel: risk,
      riskReason: m.riskHumanReason,
      output: m.executionOutput,
      exitCode: m.executionExitCode,
      pendingConfirmation: false,
      blocked: risk == RiskLevel.blocked ||
          risk == RiskLevel.blockedByMode ||
          risk == RiskLevel.blockedByWorkspace,
      blockedReason: m.blockedReason,
      wasStopped: m.executionWasStopped,
      isError: m.isError,
    );
  }
}
