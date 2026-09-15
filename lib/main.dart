import 'package:flutter/material.dart';

import 'src/app/bomban_futbol_app.dart';
import 'src/app/error_report.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Errors that happen anywhere in the game are caught, shown on screen
  // and made copyable (مطلب: عرض الخطأ أثناء اللعب مع إمكانية النسخ).
  installErrorHandlers();
  runGuardedApp(() => runApp(const BombanFutbolApp()));
}
