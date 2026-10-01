import 'dart:io';

/// Native desktop clients read the server-generated token directly from the
/// user's private app-data file. The unauthenticated HTTP bootstrap endpoint
/// is reserved for the same-origin web build.
Future<String?> loadLocalApiTokenFromDisk() async {
  final explicitHome = Platform.environment['AITERM_HOME'];
  final userHome = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if ((explicitHome == null || explicitHome.isEmpty) && (userHome == null || userHome.isEmpty)) {
    return null;
  }

  final appDir = explicitHome != null && explicitHome.isNotEmpty
      ? explicitHome
      : '$userHome${Platform.pathSeparator}.ai-terminal';
  final file = File('$appDir${Platform.pathSeparator}local_api_token.txt');
  try {
    final token = (await file.readAsString()).trim();
    return token.isEmpty ? null : token;
  } on FileSystemException {
    return null;
  }
}
