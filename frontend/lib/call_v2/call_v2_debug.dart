import 'package:flutter/foundation.dart';

void callV2Log(String scope, String message) {
  debugPrint('[V2/$scope] $message');
}
