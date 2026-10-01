// api_client.dart
// Client for the local FastAPI backend (server/). Every request needs the
// local bearer token (see server/app/main.py for the security rationale).

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

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
    final resp = await http.get(Uri.parse('$_effectiveBase/local-token'));
    if (resp.statusCode == 200) {
      _token = jsonDecode(resp.body)['token'];
    } else {
      throw Exception('Could not reach the local service. Is the server running?');
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
    if (resp.statusCode != 200) throw Exception('Failed to save the API key');
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
      }),
    );
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['detail'] ?? 'Unknown server error');
    }
    return ChatResult.fromJson(jsonDecode(resp.body));
  }

  Future<ExecuteResult> execute(String command,
      {required String mode, String? workingDir, bool userConfirmed = false, String? confirmationPhrase}) async {
    await ensureToken();
    final resp = await http.post(
      Uri.parse('$_effectiveBase/execute?mode=$mode'),
      headers: _headers,
      body: jsonEncode({
        'command': command,
        'working_dir': workingDir,
        'user_confirmed': userConfirmed,
        'confirmation_phrase': confirmationPhrase,
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

  Future<WebSocketChannel> connectExecutionSocket() async {
    await ensureToken();
    final uri = Uri.parse('$_wsBase/ws/execute?token=$_token');
    return WebSocketChannel.connect(uri);
  }
}
