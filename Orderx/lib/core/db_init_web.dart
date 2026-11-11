// Web-specific database initialization
Future<void> initDbForPlatform() async {
  // Web doesn't need sqflite initialization
  // Web apps typically use IndexedDB or other web storage solutions
  print('Database initialization skipped for web platform');
}
