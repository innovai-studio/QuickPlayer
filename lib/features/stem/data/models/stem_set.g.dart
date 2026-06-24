// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stem_set.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StemSetAdapter extends TypeAdapter<StemSet> {
  @override
  final int typeId = 5;

  @override
  StemSet read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StemSet(
      trackId: fields[0] as String,
      drumsPath: fields[1] as String,
      bassPath: fields[2] as String,
      otherPath: fields[3] as String,
      vocalsPath: fields[4] as String,
      segmentSeconds: fields[5] as double,
      createdAtMs: fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, StemSet obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.trackId)
      ..writeByte(1)
      ..write(obj.drumsPath)
      ..writeByte(2)
      ..write(obj.bassPath)
      ..writeByte(3)
      ..write(obj.otherPath)
      ..writeByte(4)
      ..write(obj.vocalsPath)
      ..writeByte(5)
      ..write(obj.segmentSeconds)
      ..writeByte(6)
      ..write(obj.createdAtMs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StemSetAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
