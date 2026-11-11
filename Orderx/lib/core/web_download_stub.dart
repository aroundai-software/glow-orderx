// Stub for non-web platforms
Future<void> saveBackupOnWeb(String content, String filename) async {
  throw UnsupportedError('Web download is only available on Web platform');
}
