import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase 初期化
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. エミュレーター接続（開発環境のみ、初期化直後・他の操作の前に）
  if (kDebugMode) {
    FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  }

  // 3. アプリ起動
  runApp(const ProviderScope(child: App()));
}
