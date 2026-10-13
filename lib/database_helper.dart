import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class Folder {
  final int? id;
  final String name;
  final String createdAt;

  const Folder({this.id, required this.name, required this.createdAt});

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {if (id != null) 'id': id, 'name': name, 'created_at': createdAt};
  }
}

class CardRecord {
  final int? id;
  final String title;
  final String suit;
  final String notes;
  final String? imageRef;
  final int folderId;

  const CardRecord({
    this.id,
    required this.title,
    required this.suit,
    this.notes = '',
    this.imageRef,
    required this.folderId,
  });

  factory CardRecord.fromMap(Map<String, dynamic> map) {
    return CardRecord(
      id: map['id'] as int?,
      title: map['title'] as String,
      suit: map['suit'] as String,
      notes: (map['notes'] as String?) ?? '',
      imageRef: map['image_ref'] as String?,
      folderId: map['folder_id'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'suit': suit,
      'notes': notes,
      'image_ref': imageRef,
      'folder_id': folderId,
    };
  }
}

// Convenience wrapper so getFoldersWithCounts() can return both.
class FolderWithCount {
  final Folder folder;
  final int cardCount;
  const FolderWithCount({required this.folder, required this.cardCount});
}

// ---------------------------------------------------------------------------
// DatabaseHelper
// ---------------------------------------------------------------------------

class DatabaseHelper {
  // --- Part I constants (unchanged, so the existing UI keeps working) -----
  static const String _databaseName = 'MyDatabase.db';
  static const int _databaseVersion = 2;

  static const String tableName = 'my_table';
  static const String columnId = '_id';
  static const String columnName = 'name';
  static const String columnAge = 'age';

  // --- Part II constants -------------------------------------------------
  static const String tableFolders = 'folders';
  static const String tableCards = 'cards';

  Database? _db;

  Future<void> init() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    _db = await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createPartOneTables(db);
        await _createCatalogueTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createCatalogueTables(db);
        }
      },
    );
  }

  // --- Schema helpers ----------------------------------------------------

  Future<void> _createPartOneTables(Database db) async {
    await db.execute('''
      CREATE TABLE $tableName (
        $columnId INTEGER PRIMARY KEY,
        $columnName TEXT NOT NULL,
        $columnAge INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createCatalogueTables(Database db) async {
    await db.execute('''
      CREATE TABLE $tableFolders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableCards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        suit TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        image_ref TEXT,
        folder_id INTEGER NOT NULL,
        FOREIGN KEY (folder_id) REFERENCES $tableFolders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_cards_folder_id ON $tableCards(folder_id)',
    );
  }

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('DatabaseHelper.init() must be awaited before use.');
    }
    return database;
  }

  // -----------------------------------------------------------------------
  // Part I methods — kept exactly as before so Activity 08 UI still works.
  // -----------------------------------------------------------------------

  Future<int> insert(Map<String, dynamic> row) async {
    return await db.insert(tableName, row);
  }

  Future<List<Map<String, dynamic>>> queryAllRows() async {
    return await db.query(tableName, orderBy: '$columnId ASC');
  }

  Future<int> queryRowCount() async {
    final result = await db.rawQuery('SELECT COUNT(*) FROM $tableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> update(Map<String, dynamic> row) async {
    final id = row[columnId];
    return await db.update(
      tableName,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    return await db.delete(tableName, where: '$columnId = ?', whereArgs: [id]);
  }

  // -----------------------------------------------------------------------
  // Part II — folder / card repository
  // -----------------------------------------------------------------------

  Future<int> insertFolder(Folder folder) async {
    return await db.insert(tableFolders, folder.toMap());
  }

  Future<List<FolderWithCount>> getFoldersWithCounts() async {
    final rows = await db.rawQuery('''
      SELECT f.id           AS id,
             f.name         AS name,
             f.created_at   AS created_at,
             COUNT(c.id)    AS card_count
      FROM $tableFolders f
      LEFT JOIN $tableCards c ON c.folder_id = f.id
      GROUP BY f.id
      ORDER BY f.name COLLATE NOCASE ASC
    ''');

    return rows.map((r) {
      final folder = Folder(
        id: r['id'] as int,
        name: r['name'] as String,
        createdAt: r['created_at'] as String,
      );
      final count = (r['card_count'] as int?) ?? 0;
      return FolderWithCount(folder: folder, cardCount: count);
    }).toList();
  }

  Future<List<CardRecord>> getCards(int folderId) async {
    final rows = await db.query(
      tableCards,
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return rows.map(CardRecord.fromMap).toList();
  }

  Future<int> insertCard(CardRecord card) async {
    return await db.insert(tableCards, card.toMap());
  }

  Future<int> updateCard(CardRecord card) async {
    assert(card.id != null, 'updateCard requires a non-null id');
    return await db.update(
      tableCards,
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<int> deleteCard(int cardId) async {
    return await db.delete(tableCards, where: 'id = ?', whereArgs: [cardId]);
  }

  Future<int> deleteFolder(int folderId) async {
    return await db.delete(
      tableFolders,
      where: 'id = ?',
      whereArgs: [folderId],
    );
  }
}
