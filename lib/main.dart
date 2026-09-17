import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'src/app/bomban_futbol_app.dart';
import 'src/app/error_report.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Use the SQLite FFI implementation on desktop (Windows) so the game
  // stores its data in a real database instead of a raw JSON file
  // (مطلب: قاعدة بيانات أقوى من جسون).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // Errors that happen anywhere in the game are caught, shown on screen
  // and made copyable (مطلب: عرض الخطأ أثناء اللعب مع إمكانية النسخ).
  installErrorHandlers();
  runGuardedApp(() => runApp(const BombanFutbolApp()));
}
