// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'partner.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PartnerAdapter extends TypeAdapter<Partner> {
  @override
  final int typeId = 0;

  @override
  Partner read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Partner(
      id: fields[0] as int,
      namaToko: fields[1] as String,
      deskripsi: fields[2] as String,
      alamat: fields[3] as String,
      noTelepon: fields[4] as String,
      latitude: fields[5] as double,
      longitude: fields[6] as double,
      hariBuka: fields[7] as String,
      jamBuka: fields[8] as String,
      jamTutup: fields[9] as String,
      fotoToko: fields[10] as String,
      createdAt: fields[11] as DateTime,
      menu: (fields[12] as List).cast<Menu>(),
    );
  }

  @override
  void write(BinaryWriter writer, Partner obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.namaToko)
      ..writeByte(2)
      ..write(obj.deskripsi)
      ..writeByte(3)
      ..write(obj.alamat)
      ..writeByte(4)
      ..write(obj.noTelepon)
      ..writeByte(5)
      ..write(obj.latitude)
      ..writeByte(6)
      ..write(obj.longitude)
      ..writeByte(7)
      ..write(obj.hariBuka)
      ..writeByte(8)
      ..write(obj.jamBuka)
      ..writeByte(9)
      ..write(obj.jamTutup)
      ..writeByte(10)
      ..write(obj.fotoToko)
      ..writeByte(11)
      ..write(obj.createdAt)
      ..writeByte(12)
      ..write(obj.menu);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartnerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
