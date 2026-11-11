import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'platform_helpers.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String dbPath = await getDatabasesPath();
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS)) {
      final appSupportDir = await getApplicationSupportDirectory();
      dbPath = appSupportDir.path;
      await ensureDirExists(dbPath);
    }
    String path = join(dbPath, 'sales_qr_app.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 Upgrading database from $oldVersion to $newVersion');
    if (oldVersion < 2) {
      try {
        await db.execute(
            'ALTER TABLE sales_orders ADD COLUMN shipping_address TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE sales_orders ADD COLUMN remarks TEXT');
      } catch (_) {}
    }

    if (oldVersion < 3) {
      await _createOfflineTables(db);
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE products_cache ADD COLUMN mrp REAL');
      } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createOfflineTables(db);

    // Create users table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        mobile_number TEXT NOT NULL,
        name TEXT NOT NULL,
        user_type TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    // Create products table
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
       ItemName TEXT NOT NULL,
        PartNumber TEXT,
        ItemRate REAL NOT NULL,
        ItemUnit TEXT NOT NULL,
        GstRate REAL NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    // Create sales_orders table
    await db.execute('''
      CREATE TABLE sales_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT NOT NULL UNIQUE,
        salesman_id TEXT NOT NULL,
        customer_id TEXT,
        order_date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        gst_amount REAL NOT NULL,
        net_amount REAL NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        shipping_address TEXT,
        remarks TEXT,
        synced_to_tally INTEGER DEFAULT 0,
        tally_sync_date TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (salesman_id) REFERENCES users (id)
      )
    ''');

    // Create order_items table
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id TEXT NOT NULL,
        ItemName TEXT NOT NULL,
        PartNumber TEXT,
        ItemQuantity INTEGER NOT NULL,
        ItemRate REAL NOT NULL,
        GstRate REAL NOT NULL,
        gst_amount REAL NOT NULL,
        total_amount REAL NOT NULL,
        FOREIGN KEY (order_id) REFERENCES sales_orders (id),
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');
  }

  Future<void> _createOfflineTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers_cache (
        id TEXT PRIMARY KEY,
        company_id TEXT,
        customer_name TEXT NOT NULL,
        mobile_number TEXT,
        address TEXT,
        city TEXT,
        state TEXT,
        pincode TEXT,
        gst_number TEXT,
        customer_category_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS products_cache (
        id TEXT PRIMARY KEY,
        company_id TEXT,
        ItemName TEXT NOT NULL,
        PartNumber TEXT,
        ItemAlias1 TEXT,
        ItemUnit TEXT,
        ItemRate REAL NOT NULL,
        GstRate REAL NOT NULL,
        ItemQuantity INTEGER,
        is_active INTEGER,
        discount_percentage REAL,
        mrp REAL,
        image_url TEXT,
        image_path TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'queued',
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
