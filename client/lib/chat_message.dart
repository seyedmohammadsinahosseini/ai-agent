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
  final List<ChatAttachmentBadge> attachments;

  ChatMessageItem({
    required this.isUser,
    required this.text,
    this.mode,
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
    this.attachments = const [],
  });
}
