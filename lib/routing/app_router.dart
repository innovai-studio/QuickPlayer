import 'package:go_router/go_router.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/player/presentation/screens/player_screen.dart';
import '../features/playlist/presentation/screens/playlist_detail_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/player/:trackId',
      builder: (context, state) {
        final trackId = state.pathParameters['trackId']!;
        return PlayerScreen(trackId: trackId);
      },
    ),
    GoRoute(
      path: '/playlist/:playlistId',
      builder: (context, state) {
        final playlistId = state.pathParameters['playlistId']!;
        return PlaylistDetailScreen(playlistId: playlistId);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
