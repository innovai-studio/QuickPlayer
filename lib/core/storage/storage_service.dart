import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/library/data/models/track.dart';
import '../../features/player/data/models/marker.dart';
import '../../features/playlist/data/models/playlist.dart';
import '../constants/app_constants.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late Box<Track> _tracksBox;
  late Box<Marker> _markersBox;
  late Box<dynamic> _settingsBox;
  late Box<Playlist> _playlistsBox;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    final appDocDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocDir.path);

    // Register adapters
    Hive.registerAdapter(TrackAdapter());
    Hive.registerAdapter(MarkerAdapter());
    Hive.registerAdapter(PlaylistAdapter());

    // Open boxes
    _tracksBox = await Hive.openBox<Track>(AppConstants.tracksBox);
    _markersBox = await Hive.openBox<Marker>(AppConstants.markersBox);
    _settingsBox = await Hive.openBox(AppConstants.settingsBox);
    _playlistsBox = await Hive.openBox<Playlist>(AppConstants.playlistsBox);

    _isInitialized = true;
  }

  // Track operations
  List<Track> getAllTracks() {
    return _tracksBox.values.toList();
  }

  Track? getTrack(String id) {
    return _tracksBox.get(id);
  }

  Future<void> saveTrack(Track track) async {
    await _tracksBox.put(track.id, track);
  }

  Future<void> deleteTrack(String id) async {
    await _tracksBox.delete(id);
    // Also delete associated markers
    final markersToDelete = _markersBox.values
        .where((m) => m.trackId == id)
        .map((m) => m.id)
        .toList();
    for (final markerId in markersToDelete) {
      await _markersBox.delete(markerId);
    }
  }

  // Marker operations
  List<Marker> getMarkersForTrack(String trackId) {
    return _markersBox.values
        .where((m) => m.trackId == trackId)
        .toList()
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
  }

  Future<void> saveMarker(Marker marker) async {
    await _markersBox.put(marker.id, marker);
  }

  Future<void> deleteMarker(String id) async {
    await _markersBox.delete(id);
  }

  // Settings operations
  T? getSetting<T>(String key) {
    return _settingsBox.get(key) as T?;
  }

  Future<void> setSetting<T>(String key, T value) async {
    await _settingsBox.put(key, value);
  }

  // Last played track
  String? get lastTrackId => getSetting<String>('lastTrackId');
  Future<void> setLastTrackId(String id) => setSetting('lastTrackId', id);

  // Playlist operations
  List<Playlist> getAllPlaylists() {
    return _playlistsBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Playlist? getPlaylist(String id) {
    return _playlistsBox.get(id);
  }

  Future<void> savePlaylist(Playlist playlist) async {
    await _playlistsBox.put(playlist.id, playlist);
  }

  Future<void> deletePlaylist(String id) async {
    await _playlistsBox.delete(id);
  }

  /// Get tracks for a playlist (resolves track IDs to Track objects)
  List<Track> getTracksForPlaylist(Playlist playlist) {
    return playlist.trackIds
        .map((id) => _tracksBox.get(id))
        .whereType<Track>()
        .toList();
  }
}
