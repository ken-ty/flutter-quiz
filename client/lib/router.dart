import 'package:go_router/go_router.dart';

import 'views/login_view.dart';
import 'views/register_view.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    // TODO: 認証状態に基づくリダイレクト（Phase 1 で実装）
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginView(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterView(),
    ),
    // TODO: Phase 4 で追加
    // GoRoute(path: '/session/:sessionId', ...),
    // TODO: Phase 5 で追加
    // GoRoute(path: '/mypage', ...),
    // GoRoute(path: '/mypage/:sessionId', ...),
  ],
);
