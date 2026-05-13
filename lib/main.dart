import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';

void main() {
  // Initialize the binding explicitly so MethodChannels are usable from any
  // initState callback without an extra microtask on first frame.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: PosbonApp()));
}
