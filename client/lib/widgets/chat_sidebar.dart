import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';

/// Collapsible left sidebar: "New Chat" button + the list of past
/// conversations (sidebar chat history), matching the familiar
/// ChatGPT/Claude-style layout.
class ChatSidebar extends StatelessWidget {
  final bool open;
  final List<ChatSummary> chats;
  final String? activeChatId;
  final bool loading;
  final VoidCallback onToggle;
  final VoidCallback onNewChat;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<String> onDeleteChat;

  static const double width = 272;

  const ChatSidebar({
    super.key,
    required this.open,
    required this.chats,
    required this.activeChatId,
    required this.loading,
    required this.onToggle,
    required this.onNewChat,
    required this.onOpenChat,
    required this.onDeleteChat,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: open ? width : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onToggle: onToggle, onNewChat: onNewChat),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: _buildList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
          ),
        ),
      );
    }
    if (chats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'No conversations yet. Start one with "New Chat".',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: chats.length,
      itemBuilder: (ctx, i) {
        final chat = chats[i];
        final isActive = chat.id == activeChatId;
        return _ChatRow(
          chat: chat,
          isActive: isActive,
          onTap: () => onOpenChat(chat.id),
          onDelete: () => onDeleteChat(chat.id),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onToggle;
  final VoidCallback onNewChat;
  const _Header({required this.onToggle, required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Collapse sidebar',
            icon: const Icon(Icons.menu_open_rounded, size: 20, color: AppColors.textSecondary),
            onPressed: onToggle,
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onNewChat,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: AppColors.textPrimary),
                    SizedBox(width: 6),
                    Text('New Chat', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRow extends StatefulWidget {
  final ChatSummary chat;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatRow({
    required this.chat,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: widget.isActive ? AppColors.surfaceHighlight : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 16, color: widget.isActive ? AppColors.accent : AppColors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isActive ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 13.5,
                        fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (_hovering || widget.isActive)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: widget.onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
