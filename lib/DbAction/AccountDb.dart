import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AccountDb {
  final String? uuid;
  final String name;
  final int? online;

  AccountDb({this.uuid, this.name = '', this.online});

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'name': name,
      'online': online,
    };
  }
}

class AccountDbAction {
  static Database? database;

  final String? uuid;
  final String name;
  final int? online;

  AccountDbAction({this.uuid, this.name = '', this.online});

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'name': name,
      'online': online,
    };
  }

  // init
  static Future<Database> initDatabase() async {
    database = await openDatabase(
      join(await getDatabasesPath(), 'config.db'),
      onCreate: (db, version) => db.execute(
          'CREATE TABLE todos(uuid TEXT PRIMARY KEY, name TEXT, online INTEGER)'),
      version: 1,
    );
    print('database initialized!');
    return database!;
  }

  // 连接
  static Future<Database> getDBConnect() async {
    if (database != null) {
      return database!;
    }
    return await initDatabase();
  }

  // 创建
  static Future<void> addAction(AccountDbAction action) async {
    final Database db = await getDBConnect();
    await db.insert(
      'actions',
      action.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 读取
  static Future<List<AccountDbAction>> getActions() async {
    final Database db = await getDBConnect();
    final List<Map<String, dynamic>> maps = await db.query('actions');
    return List.generate(maps.length, (i) {
      return AccountDbAction(
        uuid: maps[i]['uuid'],
        name: maps[i]['name'],
        online: maps[i]['online'],
      );
    });
  }

  // 更新
  static Future<void> updateAction(AccountDbAction action) async {
    final Database db = await getDBConnect();
    await db.update(
      'actions',
      action.toMap(),
      where: 'uuid = ?',
      whereArgs: [action.uuid],
    );
  }

  // 删除
  static Future<void> deleteTodo(String uuid) async {
    final Database db = await getDBConnect();
    await db.delete(
      'todos',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }
}