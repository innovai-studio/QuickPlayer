// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'marker.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MarkerAdapter extends TypeAdapter<Marker> {
  @override
  final int typeId = 1;

  @override
  Marker read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Marker(
      id: fields[0] as String,
      trackId: fields[1] as String,
      positionMs: fields[2] as int,
      label: fields[3] as String,
      colorValue: fields[4] as int,
      createdAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Marker obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.trackId)
      ..writeByte(2)
      ..write(obj.positionMs)
      ..writeByte(3)
      ..write(obj.label)
      ..writeByte(4)
      ..write(obj.colorValue)
      ..writeByte(5)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
