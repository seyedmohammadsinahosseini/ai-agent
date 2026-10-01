import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'theme.dart';
import 'models_ui.dart';
import 'chat_message.dart';
import 'widgets/mode_switch.dart';
import 'widgets/folder_picker_dialog.dart';
import 'widgets/model_panel.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/voice_input_button.dart';
import 'widgets/attachment_button.dart';
import 'widgets/workdir_button.dart';
import 'widgets/confirm_dialogs.dart';
import 'widgets/chat_sidebar.dart';

void main() {
  runApp(const AiTerminalApp());
}

class AiTerminalApp extends StatelessWidget {
  const AiTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Terminal',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const ChatScreen(),
    );
  }
}

Color riskColor(RiskLevel r) {
  switch (r) {
    case RiskLevel.safe:
      return AppColors.safe;
    case RiskLevel.confirm:
      return AppColors.confirm;
    case RiskLevel.dangerous:
      return AppColors.dangerous;
    case RiskLevel.blocked:
    case RiskLevel.blockedByMode:
    case RiskLevel.blockedByWorkspace:
      return AppColors.blocked;
    case RiskLevel.busy:
      return AppColors.textMuted;
  }
}

String riskLabel(RiskLevel r) {
  switch (r) {
    case RiskLevel.safe:
      return 'Safe · auto-run';
    case RiskLevel.confirm:
      return 'Needs your confirmation';
    case RiskLevel.dangerous:
      return 'Dangerous · needs explicit confirmation';
    case RiskLevel.blocked:
      return 'Blocked · will never run';
    case RiskLevel.blockedByMode:
      return 'Blocked in Plan mode';
    case RiskLevel.blockedByWorkspace:
      return 'Blocked by workspace guard';
    case RiskLevel.busy:
      return 'Busy';
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiClient _api = ApiClient(
    baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: ''),
  );
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessageItem> _messages = [];
  final List<PendingAttachment> _pendingAttachments = [];
  final Map<PendingAttachment, String> _uploadedIds = {};
  final Set<PendingAttachment> _uploadsInProgress = {};

  bool _sending = false;
  String? _connectionError;
  AgentMode _mode = AgentMode.plan;
  String? _workingDir;
  ProvidersStatus? _providersStatus;
  ModelInfo? _selectedModel;
  bool _modelPanelOpen = true;

  // ---------------------------- Chat history (left sidebar) ----------------------------
  bool _sidebarOpen = true;
  List<ChatSummary> _chats = [];
  bool _chatsLoading = true;
  String? _currentChatId;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  ChatMessageItem? _activeExecutionMessage;
  bool _isExecuting = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _api.ensureToken();
      setState(() => _connectionError = null);
      await _refreshProviders();
      await _refreshChatList();
    } catch (e) {
      setState(() => _connectionError = e.toString());
    }
  }

  // ---------------------------- Chat history (left sidebar) ----------------------------

  Future<void> _refreshChatList() async {
    try {
      final chats = await _api.listChats();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _chatsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _chatsLoading = false);
    }
  }

  void _startNewChat() {
    if (_uploadsInProgress.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for the attachment upload to finish first.')),
      );
      return;
    }
    _discardAllPendingContextUploads();
    setState(() {
      _messages.clear();
      _currentChatId = null;
      _pendingAttachments.clear();
      _uploadedIds.clear();
      _uploadsInProgress.clear();
    });
  }

  Future<void> _openChat(String chatId) async {
    try {
      final detail = await _api.getChat(chatId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(detail.messages.map((m) => ChatMessageItem.fromHistory(m)));
        _currentChatId = chatId;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cleanErrorMessage(e)), backgroundColor: AppColors.blocked),
        );
      }
    }
  }

  Future<void> _deleteChat(String chatId) async {
    final wasActive = _currentChatId == chatId;
    try {
      await _api.deleteChat(chatId);
      if (!mounted) return;
      setState(() {
        _chats.removeWhere((c) => c.id == chatId);
        if (wasActive) {
          _messages.clear();
          _currentChatId = null;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cleanErrorMessage(e)), backgroundColor: AppColors.blocked),
        );
      }
    }
  }

  Future<void> _refreshProviders() async {
    try {
      final status = await _api.providersStatus();
      setState(() {
        _providersStatus = status;
        final selectedStillExists = _selectedModel != null && status.availableModels.any(
          (m) => m.id == _selectedModel!.id && m.provider == _selectedModel!.provider,
        );
        if (!selectedStillExists) {
          _selectedModel = status.availableModels.isEmpty ? null : status.availableModels.first;
        }
      });
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Strips Dart's "Exception: " wrapper so the server's already-friendly
  /// error message (see ai_providers.py's _http_error_message) is shown to
  /// the user as-is, without confusing programming-language noise.
  String _cleanErrorMessage(Object e) {
    final text = e.toString();
    return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
  }

  // ---------------------------- Working folder ----------------------------

  Future<void> _openFolderPicker() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => FolderPickerDialog(api: _api, initialPath: _workingDir),
    );
    if (selected == null) return;
    setState(() => _workingDir = selected);
  }

  // ---------------------------- Attachments ----------------------------

  void _discardAttachment(PendingAttachment attachment) {
    final uploadId = _uploadedIds.remove(attachment);
    setState(() => _pendingAttachments.remove(attachment));
    if (attachment.kind == 'context' && uploadId != null) {
      unawaited(_api.deleteContextUpload(uploadId).catchError((_) {}));
    }
  }

  void _discardAllPendingContextUploads() {
    for (final attachment in List<PendingAttachment>.from(_pendingAttachments)) {
      final uploadId = _uploadedIds[attachment];
      if (attachment.kind == 'context' && uploadId != null) {
        unawaited(_api.deleteContextUpload(uploadId).catchError((_) {}));
      }
    }
  }

  Future<void> _onAttached(PendingAttachment att) async {
    setState(() {
      _pendingAttachments.add(att);
      _uploadsInProgress.add(att);
    });
    try {
      final result = await _api.upload(att.filename, att.bytes,
          kind: att.kind, workingDir: att.kind == 'workspace' ? _workingDir : null);
      if (!mounted) return;
      if (!_pendingAttachments.contains(att)) {
        _uploadsInProgress.remove(att);
        if (att.kind == 'context') {
          unawaited(_api.deleteContextUpload(result.id).catchError((_) {}));
        }
        return;
      }
      setState(() {
        _uploadedIds[att] = result.id;
        _uploadsInProgress.remove(att);
      });
      if (att.kind == 'workspace') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${result.filename}" to the working folder.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingAttachments.remove(att);
        _uploadsInProgress.remove(att);
        _uploadedIds.remove(att);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${_cleanErrorMessage(e)}'), backgroundColor: AppColors.blocked),
      );
    }
  }

  // ---------------------------- Sending a message ----------------------------

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    if (_uploadsInProgress.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for the attachment upload to finish.')),
      );
      return;
    }
    if (_selectedModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect an AI provider and choose a model first.'),
          backgroundColor: AppColors.blocked,
        ),
      );
      _openSettings();
      return;
    }
    _inputController.clear();
    final requestWorkingDir = _workingDir;

    final sentAttachments = List<PendingAttachment>.from(_pendingAttachments);
    final contextAttachments = sentAttachments.where((a) => a.kind == 'context').toList();
    final workspaceAttachments = sentAttachments.where((a) => a.kind == 'workspace').toList();
    final attachmentIds = contextAttachments.map((a) => _uploadedIds[a]).whereType<String>().toList();

    final badges = _pendingAttachments
        .map((a) => ChatAttachmentBadge(filename: a.filename, kind: a.kind))
        .toList();

    setState(() {
      _messages.add(ChatMessageItem(isUser: true, text: text, mode: _mode.wireValue, attachments: badges));
      _pendingAttachments.clear();
      _sending = true;
    });
    _scrollToBottom();

    try {
      // Preserve both sides of the conversation. Sending only user turns
      // made follow-up questions lose the assistant's earlier explanation,
      // proposed command and execution result.
      final allHistory = _messages.where((m) => !m.isError).map((m) {
        var content = m.text;
        if (!m.isUser && m.suggestedCommand != null) {
          content += '\n\nProposed command: ${m.suggestedCommand!.command}';
        }
        if (!m.isUser && m.output != null && m.output!.isNotEmpty) {
          final outputForContext = m.output!.length > 20000
              ? '[earlier output truncated]\n${m.output!.substring(m.output!.length - 20000)}'
              : m.output!;
          content += '\n\nCommand output:\n$outputForContext';
        }
        if (content.length > 90000) {
          content = '[earlier message content truncated]\n${content.substring(content.length - 90000)}';
        }
        return {'role': m.isUser ? 'user' : 'assistant', 'content': content};
      }).toList();
      final history = allHistory.length > 100
          ? allHistory.sublist(allHistory.length - 100)
          : allHistory;

      final result = await _api.chat(
        history,
        provider: _selectedModel!.provider,
        model: _selectedModel!.id,
        mode: _mode.wireValue,
        workingDir: requestWorkingDir,
        attachmentIds: attachmentIds,
        chatId: _currentChatId,
      );

      final risk = result.riskLevel != null ? riskFromString(result.riskLevel) : null;
      final isNewChat = _currentChatId == null;

      setState(() {
        _currentChatId = result.chatId;
        _messages.add(ChatMessageItem(
          isUser: false,
          text: result.replyText,
          mode: result.mode,
          historyMessageId: result.assistantMessageId,
          workingDir: requestWorkingDir,
          suggestedCommand: result.suggestedCommand,
          riskLevel: risk,
          riskReason: result.riskHumanReason,
          output: result.autoExecuted ? result.executionOutput : null,
          exitCode: result.autoExecuted ? result.executionExitCode : null,
          pendingConfirmation: risk == RiskLevel.confirm || risk == RiskLevel.dangerous,
          blocked: risk == RiskLevel.blocked ||
              risk == RiskLevel.blockedByMode ||
              risk == RiskLevel.blockedByWorkspace,
          blockedReason: result.blockedReason,
        ));
      });
      // Refresh the sidebar so a brand new chat appears in the list (or an
      // existing one moves to the top / picks up its freshly-derived title).
      if (isNewChat) {
        unawaited(_refreshChatList());
      }

      if (workspaceAttachments.isNotEmpty) {
        // Already uploaded above; nothing further needed here.
      }
    } on ChatApiException catch (e) {
      final wasNewChat = _currentChatId == null;
      setState(() {
        // Even a failed request may have created/found the chat server-side
        // (e.g. a bad API key on the very first message) - keep tracking it
        // so the next message in this conversation appends correctly
        // instead of silently starting yet another chat.
        if (e.chatId != null) _currentChatId = e.chatId;
        _messages.add(ChatMessageItem(isUser: false, text: e.message, isError: true));
      });
      if (wasNewChat && e.chatId != null) {
        unawaited(_refreshChatList());
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessageItem(
          isUser: false,
          text: _cleanErrorMessage(e),
          isError: true,
        ));
      });
    } finally {
      if (mounted) {
        for (final attachment in sentAttachments) {
          final uploadId = _uploadedIds[attachment];
          if (attachment.kind == 'context' && uploadId != null) {
            unawaited(_api.deleteContextUpload(uploadId).catchError((_) {}));
          }
        }
        setState(() {
          _sending = false;
          for (final attachment in sentAttachments) {
            _uploadedIds.remove(attachment);
          }
        });
      }
      _scrollToBottom();
    }
  }

  // ---------------------------- Execution (streaming + stoppable) ----------------------------

  Future<void> _ensureSocket() async {
    if (_wsChannel != null) return;
    _wsChannel = await _api.connectExecutionSocket();
    _wsSub = _wsChannel!.stream.listen(_onSocketMessage, onError: (_) {
      if (mounted) {
        setState(() {
          _isExecuting = false;
          _activeExecutionMessage?.isStreaming = false;
          _activeExecutionMessage?.output = 'The execution connection closed unexpectedly.';
        });
      }
      _activeExecutionMessage = null;
      _wsChannel = null;
      _wsSub = null;
    }, onDone: () {
      if (mounted && _isExecuting) {
        setState(() {
          _isExecuting = false;
          _activeExecutionMessage?.isStreaming = false;
        });
      }
      _activeExecutionMessage = null;
      _wsChannel = null;
      _wsSub = null;
    });
  }

  void _onSocketMessage(dynamic raw) {
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = data['type'];
    final msg = _activeExecutionMessage;

    switch (type) {
      case 'started':
        setState(() {
          _isExecuting = true;
          msg?.isStreaming = true;
          msg?.output = '';
        });
        _scrollToBottom();
        break;
      case 'output':
        setState(() {
          if (msg != null) {
            final combined = (msg.output ?? '') + (data['data'] as String);
            msg.output = combined.length > 1000000
                ? '[earlier live output truncated]\n${combined.substring(combined.length - 1000000)}'
                : combined;
          }
        });
        _scrollToBottom();
        break;
      case 'done':
        setState(() {
          _isExecuting = false;
          msg?.isStreaming = false;
          msg?.exitCode = data['exit_code'];
          msg?.wasStopped = data['was_stopped'] ?? false;
          msg?.pendingConfirmation = false;
        });
        _activeExecutionMessage = null;
        break;
      case 'rejected':
        setState(() {
          _isExecuting = false;
          msg?.isStreaming = false;
          msg?.output = data['message'];
          if (msg?.riskLevel == RiskLevel.confirm || msg?.riskLevel == RiskLevel.dangerous) {
            msg?.pendingConfirmation = true;
          }
        });
        _activeExecutionMessage = null;
        break;
      case 'stop_ack':
        break;
    }
  }

  Future<void> _confirmAndRun(ChatMessageItem item) async {
    if (_isExecuting) return;
    if (item.mode != 'build' || _mode != AgentMode.build) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Switch to Build mode before confirming this command.')),
      );
      return;
    }
    if (_currentChatId == null || item.historyMessageId == null || item.workingDir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This command is missing its saved chat/workspace context and cannot be run safely.'),
          backgroundColor: AppColors.blocked,
        ),
      );
      return;
    }

    final cmd = item.suggestedCommand!.command;
    bool confirmed;
    String? phrase;

    if (item.riskLevel == RiskLevel.dangerous) {
      phrase = await showDangerousConfirmDialog(context, command: cmd, reason: item.riskReason ?? '');
      confirmed = phrase != null;
    } else {
      confirmed = await showSimpleConfirmDialog(context, command: cmd, reason: item.riskReason ?? '') ?? false;
    }
    if (!confirmed || _isExecuting) return;

    try {
      await _ensureSocket();
      if (!mounted) return;
      setState(() {
        item.pendingConfirmation = false;
        item.isStreaming = true;
        item.output = 'Starting command…\n';
        _activeExecutionMessage = item;
        _isExecuting = true; // lock immediately; do not wait for WS "started"
      });

      _wsChannel?.sink.add(jsonEncode({
        'type': 'run',
        'command': cmd,
        'mode': item.mode,
        'working_dir': item.workingDir,
        'user_confirmed': true,
        'confirmation_phrase': phrase,
        'chat_id': _currentChatId,
        'message_id': item.historyMessageId,
      }));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        item.isStreaming = false;
        item.pendingConfirmation = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanErrorMessage(e)), backgroundColor: AppColors.blocked),
      );
    }
  }

  ChatMessageItem? _latestPendingConfirmation() {
    for (final message in _messages.reversed) {
      if (message.pendingConfirmation && message.suggestedCommand != null) {
        return message;
      }
    }
    return null;
  }

  Future<void> _onStopPressed() async {
    final confirmed = await showStopConfirmDialog(context);
    if (confirmed != true) return;
    _wsChannel?.sink.add(jsonEncode({'type': 'stop'}));
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (_) => SettingsDialog(api: _api, onKeysChanged: _refreshProviders),
    );
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: _sidebarOpen ? 'Hide chat history' : 'Show chat history',
          icon: Icon(_sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded),
          onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
        ),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.accent, AppColors.buildColor]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.terminal, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text('AI Terminal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _modelPanelOpen ? 'Hide model panel' : 'Show model panel',
            icon: Icon(_modelPanelOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined),
            onPressed: () => setState(() => _modelPanelOpen = !_modelPanelOpen),
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          ChatSidebar(
            open: _sidebarOpen,
            chats: _chats,
            activeChatId: _currentChatId,
            loading: _chatsLoading,
            onToggle: () => setState(() => _sidebarOpen = !_sidebarOpen),
            onNewChat: _startNewChat,
            onOpenChat: _openChat,
            onDeleteChat: _deleteChat,
          ),
          Expanded(
            child: Column(
              children: [
                if (_connectionError != null)
                  Container(
                    width: double.infinity,
                    color: AppColors.blocked.withValues(alpha: 0.15),
                    padding: const EdgeInsets.all(10),
                    child: Text('Could not connect to the local server: $_connectionError',
                        style: const TextStyle(color: AppColors.dangerous, fontSize: 12.5)),
                  ),
                Expanded(
                  child: _messages.isEmpty ? _buildEmptyState() : _buildMessageList(),
                ),
                _buildComposer(),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _modelPanelOpen && _providersStatus != null
                ? ModelPanel(
                    status: _providersStatus!,
                    selectedModelId: _selectedModel?.id,
                    onSelect: (m) => setState(() => _selectedModel = m),
                    onOpenSettings: _openSettings,
                  )
                : const SizedBox(width: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.accent, AppColors.buildColor]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.terminal, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 20),
            const Text('What do you want to get done?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              _mode == AgentMode.plan
                  ? 'Plan mode: I can explore and explain, but won\'t change anything yet.'
                  : 'Build mode: I can make real changes in your selected folder.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) => _buildMessage(_messages[i]),
    );
  }

  Widget _buildMessage(ChatMessageItem m) {
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(m.text, style: const TextStyle(fontSize: 14)),
              if (m.attachments.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: m.attachments
                      .map((a) => Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(
                              a.kind == 'workspace' ? Icons.drive_folder_upload_outlined : Icons.description_outlined,
                              size: 12,
                            ),
                            label: Text(a.filename, style: const TextStyle(fontSize: 10.5)),
                            backgroundColor: AppColors.surfaceHighlight,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 620),
        decoration: BoxDecoration(
          color: m.isError ? AppColors.blocked.withValues(alpha: 0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: m.isError ? AppColors.blocked.withValues(alpha: 0.35) : AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.isError)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 14, color: AppColors.blocked),
                    const SizedBox(width: 5),
                    const Text('Something went wrong',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.blocked)),
                    const Spacer(),
                    InkWell(
                      onTap: _openSettings,
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text('Open Settings',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
                      ),
                    ),
                  ],
                ),
              ),
            if (m.mode != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(m.mode == 'plan' ? Icons.map_outlined : Icons.build_outlined,
                        size: 12, color: m.mode == 'plan' ? AppColors.planColor : AppColors.buildColor),
                    const SizedBox(width: 4),
                    Text(m.mode == 'plan' ? 'Plan' : 'Build',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: m.mode == 'plan' ? AppColors.planColor : AppColors.buildColor,
                        )),
                  ],
                ),
              ),
            Text(m.text, style: const TextStyle(fontSize: 14, height: 1.4)),
            if (m.suggestedCommand != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                    Expanded(
                      child: SelectableText(m.suggestedCommand!.command, style: monoStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
              if (m.suggestedCommand!.explanation.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(m.suggestedCommand!.explanation,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
              const SizedBox(height: 8),
              if (m.riskLevel != null)
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: riskColor(m.riskLevel!), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(riskLabel(m.riskLevel!),
                        style: TextStyle(color: riskColor(m.riskLevel!), fontSize: 11.5, fontWeight: FontWeight.w500)),
                  ],
                ),
              if (m.blocked && m.blockedReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.blocked.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.blocked.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.block, size: 14, color: AppColors.blocked),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(m.blockedReason!,
                                style: const TextStyle(fontSize: 12, color: AppColors.blocked))),
                      ],
                    ),
                  ),
                ),
              if (m.pendingConfirmation)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FilledButton.icon(
                    onPressed: _isExecuting ? null : () => _confirmAndRun(m),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Confirm & run'),
                    style: FilledButton.styleFrom(backgroundColor: riskColor(m.riskLevel!)),
                  ),
                ),
            ],
            if (m.output != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(m.output!, style: monoStyle(fontSize: 12, color: AppColors.safe)),
                    ),
                    if (m.isStreaming)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 2),
                        child: SizedBox(
                            width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                      ),
                  ],
                ),
              ),
              if (m.wasStopped)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Stopped by user',
                    style: TextStyle(fontSize: 10.5, color: AppColors.dangerous),
                  ),
                )
              else if (m.exitCode != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Exit code: ${m.exitCode}',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: m.exitCode == 0 ? AppColors.textMuted : AppColors.dangerous)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final pendingConfirmation = _latestPendingConfirmation();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pendingConfirmation != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: riskColor(pendingConfirmation.riskLevel ?? RiskLevel.confirm)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: riskColor(pendingConfirmation.riskLevel ?? RiskLevel.confirm)
                      .withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.pending_actions_rounded,
                    size: 18,
                    color: riskColor(pendingConfirmation.riskLevel ?? RiskLevel.confirm),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'A command is waiting for your approval',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pendingConfirmation.suggestedCommand!.command.replaceAll(RegExp(r'[\r\n]+'), ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _isExecuting ? null : () => _confirmAndRun(pendingConfirmation),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Review & confirm'),
                    style: FilledButton.styleFrom(
                      backgroundColor: riskColor(
                        pendingConfirmation.riskLevel ?? RiskLevel.confirm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              WorkdirButton(workingDir: _workingDir, onTap: _openFolderPicker),
              const SizedBox(width: 10),
              ModeSwitch(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
              const Spacer(),
              if (_isExecuting)
                TextButton.icon(
                  onPressed: _onStopPressed,
                  icon: const Icon(Icons.stop_rounded, size: 16, color: AppColors.blocked),
                  label: const Text('Stop', style: TextStyle(color: AppColors.blocked, fontSize: 12.5)),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.blocked.withValues(alpha: 0.10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
            ],
          ),
          if (_pendingAttachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _pendingAttachments
                  .map((a) => InputChip(
                        avatar: _uploadsInProgress.contains(a)
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.5),
                              )
                            : Icon(
                                a.kind == 'workspace'
                                    ? Icons.drive_folder_upload_outlined
                                    : Icons.description_outlined,
                                size: 14,
                              ),
                        label: Text(a.filename, style: const TextStyle(fontSize: 11.5)),
                        onDeleted: _uploadsInProgress.contains(a)
                            ? null
                            : () => _discardAttachment(a),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AttachmentButton(workspaceSelected: _workingDir != null, onAttached: _onAttached),
              const SizedBox(width: 8),
              VoiceInputButton(onTranscribed: (text) {
                setState(() {
                  _inputController.text = text;
                  _inputController.selection = TextSelection.collapsed(offset: text.length);
                });
              }),
              const SizedBox(width: 8),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: TextField(
                    controller: _inputController,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: _mode == AgentMode.plan
                          ? 'Ask a question or explore your files (read-only)...'
                          : 'Tell the agent what to build or change...',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _sending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
