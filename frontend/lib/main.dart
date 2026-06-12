import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/app.dart';
import 'services/push_service.dart';

void main() async {
  debugPrint('[STARTUP] ===== BEGIN main() ====');
  debugPrint('[STARTUP] Step 1: WidgetsFlutterBinding.ensureInitialized()');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[STARTUP] Step 1: OK');

  // Инициализация Firebase
  debugPrint('[STARTUP] Step 2: Firebase.initializeApp()');
  try {
    await Firebase.initializeApp();
    debugPrint('[STARTUP] Step 2: Firebase.initializeApp() OK');
  } catch (e, stack) {
    debugPrint('[STARTUP] 🔴 CRASH at Step 2 (Firebase.initializeApp): $e');
    debugPrint('[STARTUP] 🔴 StackTrace: $stack');
    rethrow;
  }

  // Инициализация PushService (FCM, локальные уведомления, разрешения)
  debugPrint('[STARTUP] Step 3: PushService().init()');
  try {
    await PushService().init();
    debugPrint('[STARTUP] Step 3: PushService().init() OK');
  } catch (e, stack) {
    debugPrint('[STARTUP] 🔴 CRASH at Step 3 (PushService.init): $e');
    debugPrint('[STARTUP] 🔴 StackTrace: $stack');
    rethrow;
  }

  debugPrint('[STARTUP] Step 4: runApp(const NApp())');
  runApp(const NApp());
  debugPrint('[STARTUP] ===== END main() ====');
}