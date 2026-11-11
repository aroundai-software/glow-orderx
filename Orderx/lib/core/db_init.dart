// Conditional import for database initialization
export 'db_init_io.dart' if (dart.library.html) 'db_init_web.dart';
