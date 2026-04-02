import 'package:go_router/go_router.dart';

import 'views/login_view.dart';
import 'views/home_view.dart';

final appRouter = GoRouter(
  initialLocation: '/',
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
      path: '/',
      builder: (context, state) => const HomeView(),
    ),
    // TODO: Phase 2 で追加
    // GoRoute(path: '/chunks/new', ...),
    // GoRoute(path: '/chunks/:chunkId/edit', ...),
    // TODO: Phase 3 で追加
    // GoRoute(path: '/sessions/:sessionId', ...),
    // TODO: Phase 5 で追加
    // GoRoute(path: '/sessions/:sessionId/results', ...),
  ],
);
