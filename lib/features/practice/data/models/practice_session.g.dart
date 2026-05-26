// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'practice_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PracticeSessionAdapter extends TypeAdapter<PracticeSession> {
  @override
  final int typeId = 4;

  @override
  PracticeSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PracticeSession(
      id: fields[0] as String,
      trackId: fields[1] as String,
      startedAtMs: fields[2] as int,
      durationMs: fields[3] as int,
      trackName: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PracticeSession obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.trackId)
      ..writeByte(2)
      ..write(obj.startedAtMs)
      ..writeByte(3)
      ..write(obj.durationMs)
      ..writeByte(4)
      ..write(obj.trackName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
