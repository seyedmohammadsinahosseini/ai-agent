// api_client.dart
// Client for the local FastAPI backend (server/). Every request needs the
// local bearer token (see server/app/main.py for the security rationale).

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'local_token_loader.dart';

/// Default local server address for the native Windows/desktop build (no
/// "page origin" concept exists there, unlike Flutter Web).
const String kDefaultDesktopServerUrl = 'http://127.0.0.1:8765';

class ModelInfo {
  final String id;
  final String label;
  final String provider;
  final String description;
  ModelInfo({required this.id, required this.label, required this.provider, required this.description});

  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
        id: j['id'],
        label: j['label'],
        provider: j['provider'],
        description: j['description'] ?? '',
      );
}

class CustomProviderInfo {
  final String id;
  final String label;
  final String baseUrl;
  final List<String> models;
  CustomProviderInfo({required this.id, required this.label, required this.baseUrl, required this.models});

  factory CustomProviderInfo.fromJson(Map<String, dynamic> j) => CustomProviderInfo(
        id: j['id'],
        label: j['label'],
        baseUrl: j['base_url'],
        models: List<String>.from(j['models'] ?? []),
      );
}

class ProvidersStatus {
  final List<String> configuredProviders;
  final List<ModelInfo> availableModels;
  final List<CustomProviderInfo> customProviders;
  ProvidersStatus({required this.configuredProviders, required this.availableModels, this.customProviders = const []});

  factory ProvidersStatus.fromJson(Map<String, dynamic> j) => ProvidersStatus(
        configuredProviders: List<String>.from(j['configured_providers'] ?? []),
        availableModels: (j['available_models'] as List? ?? [])
            .map((m) => ModelInfo.fromJson(m))
            .toList(),
        customProviders: (j['custom_providers'] as List? ?? [])
            .map((p) => CustomProviderInfo.fromJson(p))
            .toList(),
      );
}

class SuggestedCommand {
  final String command;
  final String explanation;
  SuggestedCommand({required this.command, required this.explanation});

  factory SuggestedCommand.fromJson(Map<String, dynamic> j) => SuggestedCommand(
        command: j['command'] ?? '',
        explanation: j['explanation'] ?? '',
      );
}

class ChatResult {
  final String replyText;
  final String mode;
  final SuggestedCommand? suggestedCommand;
  final String? riskLevel;
  final String? riskHumanReason;
  final bool autoExecuted;
  final String? executionOutput;
  final int? executionExitCode;
  final String? blockedReason;
  final String chatId;
  final String assistantMessageId;

  ChatResult({
    required this.replyText,
    required this.mode,
    this.suggestedCommand,
    this.riskLevel,
    this.riskHumanReason,
    this.autoExecuted = false,
    this.executionOutput,
    this.executionExitCode,
    this.blockedReason,
    required this.chatId,
    required this.assistantMessageId,
  });

  factory ChatResult.fromJson(Map<String, dynamic> j) => ChatResult(
        replyText: j['reply_text'] ?? '',
        mode: j['mode'] ?? 'plan',
        suggestedCommand: j['suggested_command'] != null
            ? SuggestedCommand.fromJson(j['suggested_command'])
            : null,
        riskLevel: j['risk_level'],
        riskHumanReason: j['risk_human_reason'],
        autoExecuted: j['auto_executed'] ?? false,
        executionOutput: j['execution_output'],
        executionExitCode: j['execution_exit_code'],
        blockedReason: j['blocked_reason'],
        chatId: j['chat_id'] ?? '',
        assistantMessageId: j['assistant_message_id'] ?? '',
      );
}

/// A row in the left sidebar's chat history list.
class ChatSummary {
  final String id;
  final String title;
  final String createdAt;
  final String updatedAt;
  final int messageCount;

  ChatSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> j) => ChatSummary(
        id: j['id'],
        title: j['title'] ?? 'New chat',
        createdAt: j['created_at'] ?? '',
        updatedAt: j['updated_at'] ?? '',
        messageCount: j['message_count'] ?? 0,
      );
}

/// One message as stored/replayed from a past conversation, with enough
/// metadata to redraw an assistant turn (suggested command, risk badge,
/// output) the same way it looked live.
class ChatHistoryMessage {
  final String id;
  final String role;
  final String content;
  final String createdAt;
  final bool isError;
  final String? mode;
  final String? workingDir;
  final SuggestedCommand? suggestedCommand;
  final String? riskLevel;
  final String? riskHumanReason;
  final bool autoExecuted;
  final String? executionOutput;
  final int? executionExitCode;
  final bool executionWasStopped;
  final String? blockedReason;

  ChatHistoryMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isError = false,
    this.mode,
    this.workingDir,
    this.suggestedCommand,
    this.riskLevel,
    this.riskHumanReason,
    this.autoExecuted = false,
    this.executionOutput,
    this.executionExitCode,
    this.executionWasStopped = false,
    this.blockedReason,
  });

  factory ChatHistoryMessage.fromJson(Map<String, dynamic> j) => ChatHistoryMessage(
        id: j['id'],
        role: j['role'],
        content: j['content'] ?? '',
        createdAt: j['created_at'] ?? '',
        isError: j['is_error'] ?? false,
        mode: j['mode'],
        workingDir: j['working_dir'],
        suggestedCommand:
            j['suggested_command'] != null ? SuggestedCommand.fromJson(j['suggested_command']) : null,
        riskLevel: j['risk_level'],
        riskHumanReason: j['risk_human_reason'],
        autoExecuted: j['auto_executed'] ?? false,
        executionOutput: j['execution_output'],
        executionExitCode: j['execution_exit_code'],
        executionWasStopped: j['execution_was_stopped'] ?? false,
        blockedReason: j['blocked_reason'],
      );
}

class ChatDetail {
  final String id;
  final String title;
  final List<ChatHistoryMessage> messages;

  ChatDetail({required this.id, required this.title, required this.messages});

  factory ChatDetail.fromJson(Map<String, dynamic> j) => ChatDetail(
        id: j['id'],
        title: j['title'] ?? 'New chat',
        messages: (j['messages'] as List? ?? []).map((m) => ChatHistoryMessage.fromJson(m)).toList(),
      );
}

class ExecuteResult {
  final bool executed;
  final String riskLevel;
  final String riskHumanReason;
  final String? output;
  final int? exitCode;
  final String? message;

  ExecuteResult({
    required this.executed,
    required this.riskLevel,
    required this.riskHumanReason,
    this.output,
    this.exitCode,
    this.message,
  });

  factory ExecuteResult.fromJson(Map<String, dynamic> j) => ExecuteResult(
        executed: j['executed'] ?? false,
        riskLevel: j['risk_level'] ?? 'SAFE',
        riskHumanReason: j['risk_human_reason'] ?? '',
        output: j['output'],
        exitCode: j['exit_code'],
        message: j['message'],
      );
}

class FolderEntry {
  final String name;
  final String path;
  final bool isDir;
  FolderEntry({required this.name, required this.path, required this.isDir});

  factory FolderEntry.fromJson(Map<String, dynamic> j) =>
      FolderEntry(name: j['name'], path: j['path'], isDir: j['is_dir'] ?? true);
}

class BrowseResult {
  final String currentPath;
  final String? parentPath;
  final List<FolderEntry> entries;
  BrowseResult({required this.currentPath, this.parentPath, required this.entries});

  factory BrowseResult.fromJson(Map<String, dynamic> j) => BrowseResult(
        currentPath: j['current_path'],
        parentPath: j['parent_path'],
        entries: (j['entries'] as List).map((e) => FolderEntry.fromJson(e)).toList(),
      );
}

class UploadResult {
  final String id;
  final String filename;
  final int sizeBytes;
  final String kind;
  UploadResult({required this.id, required this.filename, required this.sizeBytes, required this.kind});

  factory UploadResult.fromJson(Map<String, dynamic> j) => UploadResult(
        id: j['id'],
        filename: j['filename'],
        sizeBytes: j['size_bytes'],
        kind: j['kind'],
      );
}

/// Thrown by [ApiClient.chat] on a failed request. Carries [chatId] when the
/// server managed to create/find the conversation before the failure, so the
/// UI can still track it (e.g. a bad API key on the very first message of a
/// new chat) instead of losing it.
class ChatApiException implements Exception {
  final String message;
  final String? chatId;
  ChatApiException(this.message, {this.chatId});
  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  String? _token;

  ApiClient({required this.baseUrl});

  // On Flutter Web (this sandbox's preview build), falling back to the page's
  // own origin lets the same FastAPI process serve both the API and the
  // compiled web bundle. On the native Windows/desktop build there is no
  // "page origin" (kIsWeb is false), so we fall back to the well-known local
  // server address instead.
  String get _effectiveBase {
    if (baseUrl.isNotEmpty) return baseUrl;
    return kIsWeb ? Uri.base.origin : kDefaultDesktopServerUrl;
  }
  String get _wsBase {
    final base = _effectiveBase;
    return base.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
  }

  Future<void> ensureToken() async {
    if (_token != null) return;

    // Native desktop reads the private token file directly. Only the
    // same-origin Web build uses the loopback-restricted bootstrap endpoint.
    if (!kIsWeb) {
      _token = await loadLocalApiTokenFromDisk();
      if (_token == null) {
        throw Exception(
          'Could not read the local API token. Start the server once and make sure AITERM_HOME matches.',
        );
      }
      return;
    }

    final resp = await http.get(Uri.parse('$_effectiveBase/local-token'));
    if (resp.statusCode == 200) {
      _token = jsonDecode(resp.body)['token'];
    } else {
      throw Exception('Could not securely bootstrap the local web session. Is the server running?');
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  Future<ProvidersStatus> providersStatus() async {
    await ensureToken();
    final resp = await http.get(Uri.parse('$_effectiveBase/providers/status'), headers: _headers);
    if (resp.statusCode != 200) throw Exception('Failed to fetch provider status');
    return ProvidersStatus.fromJson(jsonDecode(resp.body));
  }

  Future<void> saveApiKey(String provider, String apiKey) async {
    await ensureToken();
    final resp = await http.post(
      Uri.parse('$_effectiveBase/providers/api-key'),
      headers: _headers,
      body: jsonEncode({'provider': provider, 'api_key': apiKey}),
    );
    if (resp.statusCode != 200) {
      try {
        final error = jsonDecode(resp.body);
        throw Exception(error['detail'] ?? 'Failed to save the API key');
      } on FormatException {
        throw Exception('Failed to save the API key');
      }
    }
  }

  /// Removes a saved built-in provider key, so the user can connect a
  /// different key/account in its place whenever they want.
  Future<void> deleteApiKey(String provider) async {
    await ensureToken();
    final resp = await http.delete(
      Uri.parse('$_effectiveBase/providers/api-key/$provider'),
      headers: _headers,
    );
    if (resp.statusCode != 200) throw Exception('Failed to remove the API key');
  }

  /// Connects an arbitrary OpenAI-API-compatible provider by URL (Groq,
  /// OpenRouter, Together, DeepSeek, a self-hosted Ollama/LM Studio server,
  /// etc.), instead of picking from the built-in presets. If [model] is left
  /// null/empty, the server tries to auto-detect which models the key can
  /// access via GET {base_url}/models.
  Future<CustomProviderInfo> addCustomProvider({
    required String label,
    required String baseUrl,
    required String apiKey,
    String? model,
  }) async {
    await ensureToken();
    final resp = await http.post(
      Uri.parse('$_effectiveBase/providers/custom'),
      headers: _headers,
      body: jsonEncode({
        'label': label,
        'base_url': baseUrl,
        'api_key': apiKey,
        if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      }),
    );
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['detail'] ?? 'Failed to connect provider');
    }
    return CustomProviderInfo.fromJson(jsonDecode(resp.body));
  }

  Future<void> deleteCustomProvider(String id) async {
    await ensureToken();
    final resp = await http.delete(
      Uri.parse('$_effectiveBase/providers/custom/$id'),
      headers: _headers,
    );
    if (resp.statusCode != 200) throw Exception('Failed to remove provider');
  }

  Future<ChatResult> chat(
    List<Map<String, String>> messages, {
    required String provider,
    String? model,
    required String mode,
    String? workingDir,
    List<String> attachmentIds = const [],
    String? chatId,
  }) async {
    await ensureToken();
    final resp = await http.post(
      Uri.parse('$_effectiveBase/chat'),
      headers: _headers,
      body: jsonEncode({
        'messages': messages,
        'provider': provider,
        'model': model,
        'mode': mode,
        'working_dir': workingDir,
        'attachment_ids': attachmentIds,
        'chat_id': chatId,
      }),
    );
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      final detail = err['detail'];
      if (detail is Map) {
        throw ChatApiException(detail['message'] ?? 'Unknown server error', chatId: detail['chat_id']);
      }
      throw ChatApiException(detail ?? 'Unknown server error');
    }
    return ChatResult.fromJson(jsonDecode(resp.body));
  }

  // ---------------------------- Chat history (left sidebar) ----------------------------

  Future<List<ChatSummary>> listChats() async {
    await ensureToken();
    final resp = await http.get(Uri.parse('$_effectiveBase/chats'), headers: _headers);
    if (resp.statusCode != 200) throw Exception('Failed to load chat history');
    final data = jsonDecode(resp.body);
    return (data['chats'] as List? ?? []).map((c) => ChatSummary.fromJson(c)).toList();
  }

  Future<ChatDetail> getChat(String chatId) async {
    await ensureToken();
    final resp = await http.get(Uri.parse('$_effectiveBase/chats/$chatId'), headers: _headers);
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['detail'] ?? 'Failed to open this chat');
    }
    return ChatDetail.fromJson(jsonDecode(resp.body));
  }

  Future<void> renameChat(String chatId, String title) async {
    await ensureToken();
    final resp = await http.patch(
      Uri.parse('$_effectiveBase/chats/$chatId'),
      headers: _headers,
      body: jsonEncode({'title': title}),
    );
    if (resp.statusCode != 200) throw Exception('Failed to rename chat');
  }

  Future<void> deleteChat(String chatId) async {
    await ensureToken();
    final resp = await http.delete(Uri.parse('$_effectiveBase/chats/$chatId'), headers: _headers);
    if (resp.statusCode != 200) throw Exception('Failed to delete chat');
  }

  Future<ExecuteResult> execute(String command,
      {required String mode,
      String? workingDir,
      bool userConfirmed = false,
      String? confirmationPhrase,
      String? chatId,
      String? messageId}) async {
    await ensureToken();
    final resp = await http.post(
      Uri.parse('$_effectiveBase/execute?mode=$mode'),
      headers: _headers,
      body: jsonEncode({
        'command': command,
        'working_dir': workingDir,
        'user_confirmed': userConfirmed,
        'confirmation_phrase': confirmationPhrase,
        'chat_id': chatId,
        'message_id': messageId,
      }),
    );
    if (resp.statusCode != 200) throw Exception('Execution failed');
    return ExecuteResult.fromJson(jsonDecode(resp.body));
  }

  Future<BrowseResult> browse(String? path) async {
    await ensureToken();
    final uri = Uri.parse('$_effectiveBase/workspace/browse')
        .replace(queryParameters: path != null ? {'path': path} : null);
    final resp = await http.get(uri, headers: _headers);
    if (resp.statusCode != 200) throw Exception('Failed to browse folder');
    return BrowseResult.fromJson(jsonDecode(resp.body));
  }

  Future<UploadResult> upload(
    String filename,
    Uint8List bytes, {
    required String kind,
    String? workingDir,
  }) async {
    await ensureToken();
    final uri = Uri.parse('$_effectiveBase/uploads');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_token';
    request.fields['kind'] = kind;
    if (workingDir != null) request.fields['working_dir'] = workingDir;
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['detail'] ?? 'Upload failed');
    }
    return UploadResult.fromJson(jsonDecode(resp.body));
  }

  Future<void> deleteContextUpload(String uploadId) async {
    await ensureToken();
    final resp = await http.delete(
      Uri.parse('$_effectiveBase/uploads/$uploadId'),
      headers: _headers,
    );
    if (resp.statusCode != 200) throw Exception('Failed to discard context upload');
  }

  Future<WebSocketChannel> connectExecutionSocket() async {
    await ensureToken();
    final response = await http.post(Uri.parse('$_effectiveBase/ws-ticket'), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Could not authorize the execution channel.');
    }
    final ticket = jsonDecode(response.body)['ticket'] as String;
    final uri = Uri.parse('$_wsBase/ws/execute').replace(queryParameters: {'ticket': ticket});
    return WebSocketChannel.connect(uri);
  }
}
