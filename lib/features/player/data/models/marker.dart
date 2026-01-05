import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'marker.g.dart';

@HiveType(typeId: 1)
class Marker extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String trackId;

  @HiveField(2)
  final int positionMs;

  @HiveField(3)
  String label;

  @HiveField(4)
  int colorValue;

  @HiveField(5)
  final DateTime createdAt;

  Marker({
    required this.id,
    required this.trackId,
    required this.positionMs,
    required this.label,
    this.colorValue = 0xFF667EEA,
    required this.createdAt,
  });

  Duration get position => Duration(milliseconds: positionMs);
  Color get color => Color(colorValue);

  Marker copyWith({
    String? id,
    String? trackId,
    int? positionMs,
    String? label,
    int? colorValue,
    DateTime? createdAt,
  }) {
    return Marker(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      positionMs: positionMs ?? this.positionMs,
      label: label ?? this.label,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Marker(id: $id, label: $label, position: $positionMs ms)';
}
