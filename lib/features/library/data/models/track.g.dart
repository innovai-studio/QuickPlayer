// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TrackAdapter extends TypeAdapter<Track> {
  @override
  final int typeId = 0;

  @override
  Track read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Track(
      id: fields[0] as String,
      name: fields[1] as String,
      filePath: fields[2] as String,
      durationMs: fields[3] as int,
      fileSize: fields[4] as int,
      mimeType: fields[5] as String?,
      createdAt: fields[6] as DateTime,
      lastPlayedAt: fields[7] as DateTime?,
      bpm: fields[8] as int?,
      musicalKey: fields[9] as String?,
      isExternal: fields[10] == null ? false : fields[10] as bool,
      focusPresetIndex: fields[11] as int?,
      customBandLevels: (fields[12] as List?)?.cast<int>(),
      customBassStrength: fields[13] as int?,
      metronomePhaseOffsetMs: fields[14] as int?,
      waveformPeaks: (fields[15] as List?)?.cast<double>(),
    );
  }

  @override
  void write(BinaryWriter writer, Track obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.filePath)
      ..writeByte(3)
      ..write(obj.durationMs)
      ..writeByte(4)
      ..write(obj.fileSize)
      ..writeByte(5)
      ..write(obj.mimeType)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.lastPlayedAt)
      ..writeByte(8)
      ..write(obj.bpm)
      ..writeByte(9)
      ..write(obj.musicalKey)
      ..writeByte(10)
      ..write(obj.isExternal)
      ..writeByte(11)
      ..write(obj.focusPresetIndex)
      ..writeByte(12)
      ..write(obj.customBandLevels)
      ..writeByte(13)
      ..write(obj.customBassStrength)
      ..writeByte(14)
      ..write(obj.metronomePhaseOffsetMs)
      ..writeByte(15)
      ..write(obj.waveformPeaks);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
