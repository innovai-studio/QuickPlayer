# QuickPlayer - 音樂練習助手

> **版本**: 1.1.0
> **日期**: 2025-12-19
> **狀態**: 規劃階段
> **框架**: Flutter

---

## 1. 應用程式概述

**QuickPlayer** 是一款專為音樂學習者設計的練習工具。它能讓使用者：
- 調整播放速度（慢練，不變調）
- 調整音調（移調）
- 標記特定段落循環播放（A-B Loop）
- 記錄練習重點（Session Mark）

**目標用戶**: 一般大眾（樂器學習者、歌唱練習者）
**平台**: iOS（優先）、Android
**資料儲存**: 純本地，無需登入

---

## 2. 核心功能模組

### 2.1 音樂播放器 (Player)

**使用者故事**: 作為使用者，我希望能選擇本地音檔並播放。

**功能需求**:
- 支援常見音頻格式（MP3, WAV, M4A, AAC, FLAC）
- 播放/暫停/停止控制
- 進度條拖曳跳轉
- 顯示當前時間 / 總時長
- 波形視覺化顯示

**技術實現**:
```dart
final player = AudioPlayer();
await player.setFilePath(filePath);
await player.play();
await player.pause();
await player.seek(Duration(seconds: 30));
```

### 2.2 速度調整 (Speed Control)

**使用者故事**: 作為使用者，我希望能放慢或加快播放速度來練習困難段落，且音調不變。

**功能需求**:
- 速度範圍：0.25x ~ 2.0x
- 預設快捷按鈕：0.5x, 0.75x, 1.0x, 1.25x, 1.5x
- 精細調整滑桿（0.05 步進）
- **變速不變調**（just_audio 原生支援）

**技術實現**:
```dart
// 變速不變調 - just_audio 自動處理
await player.setSpeed(0.75);  // 0.75倍速，音調不變
```

### 2.3 音調調整 (Pitch Shift)

**使用者故事**: 作為使用者，我希望能升降調來配合我的音域或樂器調性。

**功能需求**:
- 範圍：±12 半音（一個八度）
- 半音為單位的精確調整
- 快捷按鈕：-1, 0, +1 半音
- 可獨立於速度調整

**技術實現**:
```dart
// 音調調整 - 1.0 = 原調, 1.0595 ≈ +1半音, 0.9439 ≈ -1半音
await player.setPitch(1.0595);  // 升一個半音

// 半音換算公式
double pitchForSemitones(int semitones) {
  return pow(2, semitones / 12).toDouble();
}
```

### 2.4 A-B 段落循環 (A-B Loop)

**使用者故事**: 作為使用者，我希望能標記一個段落並重複播放，專注練習困難部分。

**功能需求**:
- 點擊「A」標記起點
- 點擊「B」標記終點
- 自動在 A-B 區間循環播放
- 視覺化顯示 A-B 範圍
- 清除 A-B 標記
- 可調整 A/B 點位置

**技術實現**:
```dart
// 使用 just_audio 的 setClip 功能
await player.setClip(
  start: Duration(seconds: 30),
  end: Duration(seconds: 45),
);
await player.setLoopMode(LoopMode.one);

// 監聽播放位置，自動循環
player.positionStream.listen((position) {
  if (position >= pointB) {
    player.seek(pointA);
  }
});
```

### 2.5 練習標記 (Session Markers)

**使用者故事**: 作為使用者，我希望能在曲目中標記重要位置，方便日後快速跳轉。

**功能需求**:
- 在任意位置新增標記
- 為標記命名（如：「副歌開始」、「困難段落」）
- 標記顏色分類
- 點擊標記快速跳轉
- 標記列表管理（查看、編輯、刪除）
- 標記持久化儲存（綁定曲目）

### 2.6 音樂庫 (Library)

**使用者故事**: 作為使用者，我希望能管理我的練習曲目。

**功能需求**:
- 從裝置選擇音檔匯入
- 曲目列表顯示（名稱、時長、最後播放時間）
- 搜尋曲目
- 刪除曲目
- 顯示每首曲目的標記數量
- 最近播放記錄

---

## 3. 技術架構

### 3.1 專案結構

```
quickplayer/
├── lib/
│   ├── main.dart                    # 應用程式入口
│   ├── app.dart                     # App 配置與路由
│   │
│   ├── core/                        # 核心功能
│   │   ├── audio/
│   │   │   ├── audio_player_service.dart    # 音頻播放服務
│   │   │   ├── audio_processor.dart         # 音頻處理（速度、音調）
│   │   │   └── waveform_generator.dart      # 波形生成
│   │   ├── storage/
│   │   │   ├── local_storage.dart           # 本地儲存服務
│   │   │   └── file_service.dart            # 檔案管理
│   │   └── constants/
│   │       ├── app_colors.dart              # 顏色定義
│   │       └── app_constants.dart           # 常數定義
│   │
│   ├── features/                    # 功能模組
│   │   ├── library/                 # 音樂庫
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   └── track.dart
│   │   │   │   └── repositories/
│   │   │   │       └── track_repository.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   └── library_screen.dart
│   │   │   │   ├── widgets/
│   │   │   │   │   ├── track_list_item.dart
│   │   │   │   │   └── import_button.dart
│   │   │   │   └── providers/
│   │   │   │       └── library_provider.dart
│   │   │   └── library.dart         # Feature barrel file
│   │   │
│   │   ├── player/                  # 播放器
│   │   │   ├── data/
│   │   │   │   └── models/
│   │   │   │       ├── marker.dart
│   │   │   │       └── ab_loop.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   └── player_screen.dart
│   │   │   │   ├── widgets/
│   │   │   │   │   ├── playback_controls.dart
│   │   │   │   │   ├── progress_bar.dart
│   │   │   │   │   ├── speed_control.dart
│   │   │   │   │   ├── pitch_control.dart
│   │   │   │   │   ├── ab_loop_control.dart
│   │   │   │   │   ├── marker_list.dart
│   │   │   │   │   └── waveform_view.dart
│   │   │   │   └── providers/
│   │   │   │       └── player_provider.dart
│   │   │   └── player.dart
│   │   │
│   │   └── settings/                # 設定
│   │       ├── presentation/
│   │       │   ├── screens/
│   │       │   │   └── settings_screen.dart
│   │       │   └── providers/
│   │       │       └── settings_provider.dart
│   │       └── settings.dart
│   │
│   ├── shared/                      # 共用元件
│   │   ├── widgets/
│   │   │   ├── glass_card.dart              # Liquid Glass 卡片
│   │   │   ├── glass_button.dart            # 玻璃質感按鈕
│   │   │   ├── glass_slider.dart            # 玻璃質感滑桿
│   │   │   └── glass_icon_button.dart       # 圖標按鈕
│   │   └── extensions/
│   │       └── duration_extension.dart      # Duration 擴展
│   │
│   └── routing/
│       └── app_router.dart          # 路由配置
│
├── assets/
│   ├── icons/                       # 自定義圖標
│   └── fonts/                       # 字體（如需要）
│
├── test/                            # 測試
│   ├── unit/
│   └── widget/
│
├── pubspec.yaml                     # 依賴配置
├── analysis_options.yaml            # Lint 規則
└── README.md
```

### 3.2 技術棧

| 類別 | 技術選擇 |
|------|----------|
| 框架 | Flutter 3.x |
| 語言 | Dart 3.x |
| 狀態管理 | Riverpod 2.x |
| 路由 | go_router |
| 音頻播放 | just_audio |
| 波形顯示 | just_waveform / audio_waveforms |
| 本地儲存 | Hive / SharedPreferences |
| 檔案選擇 | file_picker |
| UI 風格 | Liquid Glass (自定義) |
| CI/CD | Codemagic |

### 3.3 核心依賴

```yaml
# pubspec.yaml
name: quickplayer
description: 音樂練習助手

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: '>=3.16.0'

dependencies:
  flutter:
    sdk: flutter

  # 狀態管理
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0

  # 路由
  go_router: ^13.0.0

  # 音頻
  just_audio: ^0.9.36
  audio_session: ^0.1.18

  # 波形
  just_waveform: ^0.0.4
  # 或 audio_waveforms: ^1.0.5

  # 儲存
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  path_provider: ^2.1.1

  # 檔案
  file_picker: ^6.1.1

  # UI
  flutter_blur: ^1.0.0

  # 工具
  uuid: ^4.2.1
  intl: ^0.18.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  riverpod_generator: ^2.3.0
  build_runner: ^2.4.0
  hive_generator: ^2.0.1
```

---

## 4. 視覺設計

### 4.1 設計風格：Liquid Glass

延續 CatchCash 的視覺概念，使用 Flutter 重新實現 iOS 原生的毛玻璃質感。

**主要特點**:
- 深色背景
- 毛玻璃卡片 (BackdropFilter + 半透明)
- 柔和的發光效果
- Cupertino 風格圖標
- 圓角設計 (16-32px)

### 4.2 配色方案

```dart
// lib/core/constants/app_colors.dart
class AppColors {
  // 背景
  static const background = Color(0xFF0A0A0B);
  static const surfaceDark = Color(0xFF1C1C1E);

  // 主色調（漸變）
  static const primaryStart = Color(0xFF667EEA);
  static const primaryEnd = Color(0xFF764BA2);

  // 強調色
  static const accent = Color(0xFF00D9FF);      // A-B 標記
  static const success = Color(0xFF34C759);     // 播放中
  static const warning = Color(0xFFFF9500);     // 警告

  // 文字
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0x99FFFFFF);  // 60% 透明

  // 邊框與分隔
  static const border = Color(0x1FFFFFFF);      // 12% 透明
  static const divider = Color(0x33FFFFFF);     // 20% 透明

  // 卡片背景
  static const cardBackground = Color(0xB81C1C1E);  // 72% 透明
}
```

### 4.3 Liquid Glass 元件實現

```dart
// lib/shared/widgets/glass_card.dart
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: AppColors.border,
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.44),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
```

### 4.4 主要畫面設計

#### 音樂庫頁面
```
┌─────────────────────────────────┐
│  QuickPlayer              [+]  │
├─────────────────────────────────┤
│  🔍 搜尋曲目...                 │
├─────────────────────────────────┤
│  ┌───────────────────────────┐ │
│  │ 🎵 練習曲1.mp3            │ │
│  │    3:45  ●●● 3個標記      │ │
│  └───────────────────────────┘ │
│  ┌───────────────────────────┐ │
│  │ 🎵 難度挑戰.m4a           │ │
│  │    5:20  ●● 2個標記       │ │
│  └───────────────────────────┘ │
├─────────────────────────────────┤
│  [🎵 庫]         [⚙️ 設定]    │
└─────────────────────────────────┘
```

#### 播放器頁面
```
┌─────────────────────────────────┐
│  ←              練習曲1        │
├─────────────────────────────────┤
│                                 │
│     ~~~~ 波形視覺化 ~~~~        │
│     [A]━━━━━━━━━[B]            │
│                                 │
├─────────────────────────────────┤
│     1:23 ━━━━●━━━━━ 3:45      │
├─────────────────────────────────┤
│                                 │
│        ⏮   ▶️   ⏭            │
│                                 │
├─────────────────────────────────┤
│  ┌───────────────────────────┐ │
│  │ 速度              0.75x   │ │
│  │ ━━━━●━━━━━━━━━━━━━━━━━━  │ │
│  │ 0.5x  0.75x  1x  1.25x    │ │
│  └───────────────────────────┘ │
├─────────────────────────────────┤
│  ┌───────────────────────────┐ │
│  │ 音調               0      │ │
│  │ ━━━━━━━━●━━━━━━━━━━━━━━  │ │
│  │   [-]    原調    [+]      │ │
│  └───────────────────────────┘ │
├─────────────────────────────────┤
│  ┌───────────────────────────┐ │
│  │ A-B 循環                  │ │
│  │ [設定 A]     [設定 B]     │ │
│  │ [清除]       [循環: ON]   │ │
│  └───────────────────────────┘ │
├─────────────────────────────────┤
│  標記 (3)              [+ 新增] │
│  ● 0:45 前奏結束                │
│  ● 1:30 困難段落                │
│  ● 2:15 副歌開始                │
└─────────────────────────────────┘
```

---

## 5. 資料模型

### 5.1 Dart 類型定義

```dart
// lib/features/library/data/models/track.dart
import 'package:hive/hive.dart';

part 'track.g.dart';

@HiveType(typeId: 0)
class Track extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String filePath;

  @HiveField(3)
  final Duration duration;

  @HiveField(4)
  final int fileSize;

  @HiveField(5)
  final String mimeType;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  DateTime? lastPlayedAt;

  Track({
    required this.id,
    required this.name,
    required this.filePath,
    required this.duration,
    required this.fileSize,
    required this.mimeType,
    required this.createdAt,
    this.lastPlayedAt,
  });
}
```

```dart
// lib/features/player/data/models/marker.dart
@HiveType(typeId: 1)
class Marker extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String trackId;

  @HiveField(2)
  final Duration position;

  @HiveField(3)
  String label;

  @HiveField(4)
  int colorValue;  // Color.value

  @HiveField(5)
  final DateTime createdAt;

  Marker({
    required this.id,
    required this.trackId,
    required this.position,
    required this.label,
    this.colorValue = 0xFF667EEA,
    required this.createdAt,
  });

  Color get color => Color(colorValue);
}
```

```dart
// lib/features/player/data/models/ab_loop.dart
class ABLoop {
  final String trackId;
  final Duration? pointA;
  final Duration? pointB;
  final bool isActive;

  const ABLoop({
    required this.trackId,
    this.pointA,
    this.pointB,
    this.isActive = false,
  });

  bool get isComplete => pointA != null && pointB != null;

  ABLoop copyWith({
    Duration? pointA,
    Duration? pointB,
    bool? isActive,
  }) {
    return ABLoop(
      trackId: trackId,
      pointA: pointA ?? this.pointA,
      pointB: pointB ?? this.pointB,
      isActive: isActive ?? this.isActive,
    );
  }
}
```

```dart
// lib/features/player/presentation/providers/player_provider.dart
class PlayerState {
  final Track? currentTrack;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double speed;        // 0.25 - 2.0
  final int pitchSemitones;  // -12 to +12
  final ABLoop? abLoop;
  final List<Marker> markers;

  const PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.pitchSemitones = 0,
    this.abLoop,
    this.markers = const [],
  });
}
```

```dart
// lib/features/settings/data/models/settings.dart
@HiveType(typeId: 2)
class AppSettings extends HiveObject {
  @HiveField(0)
  double defaultSpeed;

  @HiveField(1)
  int defaultPitchSemitones;

  @HiveField(2)
  bool showWaveform;

  @HiveField(3)
  bool keepScreenOn;

  @HiveField(4)
  String? lastTrackId;

  AppSettings({
    this.defaultSpeed = 1.0,
    this.defaultPitchSemitones = 0,
    this.showWaveform = true,
    this.keepScreenOn = true,
    this.lastTrackId,
  });
}
```

### 5.2 儲存結構 (Hive Boxes)

```dart
// Box 名稱
const String tracksBox = 'tracks';
const String markersBox = 'markers';
const String settingsBox = 'settings';
```

---

## 6. CI/CD 配置 (Codemagic)

### 6.1 codemagic.yaml

```yaml
workflows:
  quickplayer-release:
    name: QuickPlayer Release
    max_build_duration: 60

    environment:
      flutter: stable
      xcode: latest
      cocoapods: default
      groups:
        - app_store_credentials
        - google_play_credentials

    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true

    scripts:
      - name: Get dependencies
        script: flutter pub get

      - name: Run tests
        script: flutter test

      - name: Build Android
        script: |
          flutter build apk --release
          flutter build appbundle --release

      - name: Build iOS
        script: |
          flutter build ios --release --no-codesign
          cd ios && pod install
          xcode-project use-profiles
          xcode-project build-ipa

    artifacts:
      - build/**/outputs/**/*.apk
      - build/**/outputs/**/*.aab
      - build/ios/ipa/*.ipa

    publishing:
      google_play:
        credentials: $GCLOUD_SERVICE_ACCOUNT_CREDENTIALS
        track: internal

      app_store_connect:
        api_key: $APP_STORE_CONNECT_PRIVATE_KEY
        key_id: $APP_STORE_CONNECT_KEY_IDENTIFIER
        issuer_id: $APP_STORE_CONNECT_ISSUER_ID
        submit_to_testflight: true

  quickplayer-dev:
    name: QuickPlayer Dev Build
    max_build_duration: 30

    environment:
      flutter: stable

    triggering:
      events:
        - pull_request

    scripts:
      - name: Get dependencies
        script: flutter pub get

      - name: Analyze
        script: flutter analyze

      - name: Run tests
        script: flutter test

      - name: Build APK (Debug)
        script: flutter build apk --debug

    artifacts:
      - build/**/outputs/**/*.apk
```

---

## 7. 開發階段規劃

### Phase 1：專案設置與基礎架構
- [ ] Flutter 專案初始化
- [ ] 依賴安裝與配置
- [ ] 基礎路由設置 (go_router)
- [ ] 狀態管理設置 (Riverpod)
- [ ] Hive 本地儲存設置
- [ ] Liquid Glass UI 元件庫

### Phase 2：音樂庫功能
- [ ] 檔案選擇與匯入
- [ ] 曲目列表顯示
- [ ] 曲目搜尋
- [ ] 曲目刪除
- [ ] 資料持久化

### Phase 3：核心播放器
- [ ] just_audio 整合
- [ ] 播放控制（播放/暫停/停止）
- [ ] 進度條與拖曳跳轉
- [ ] 速度調整（變速不變調）
- [ ] 音調調整

### Phase 4：練習功能
- [ ] A-B 循環標記
- [ ] A-B 循環播放邏輯
- [ ] 練習標記（新增/跳轉/刪除）
- [ ] 標記持久化
- [ ] 波形顯示

### Phase 5：完善與發布
- [ ] 設定頁面
- [ ] 錯誤處理與邊界情況
- [ ] 效能優化
- [ ] Codemagic CI/CD 設置
- [ ] App Store / Play Store 上架

---

## 8. 參考資源

### 官方文檔
- [Flutter 文檔](https://docs.flutter.dev/)
- [just_audio 文檔](https://pub.dev/packages/just_audio)
- [Riverpod 文檔](https://riverpod.dev/)
- [go_router 文檔](https://pub.dev/packages/go_router)
- [Hive 文檔](https://docs.hivedb.dev/)
- [Codemagic 文檔](https://docs.codemagic.io/)

### 音頻處理
- [just_audio GitHub](https://github.com/ryanheise/just_audio)
- [audio_session](https://pub.dev/packages/audio_session)

### UI 參考
- [CatchCash Liquid Glass 風格](../CatchCash/)

---

## 更新日誌

### v1.1.0 (2025-12-19)
- 技術棧從 Expo/React Native 改為 Flutter
- 更新專案結構為 Feature-based 架構
- 新增 just_audio 整合說明
- 新增 Codemagic CI/CD 配置
- 新增 Riverpod 狀態管理
- 更新資料模型為 Dart/Hive

### v1.0.0 (2025-12-19)
- 初始規格文件建立（Expo 版本）
