// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TransactionAdapter extends TypeAdapter<Transaction> {
  @override
  final int typeId = 1;

  @override
  Transaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Transaction(
      id: fields[0] as String,
      type: fields[1] as String,
      quantity: fields[2] as int,
      documentNumber: fields[3] as String,
      notes: fields[4] as String?,
      previousStock: fields[5] as int,
      newStock: fields[6] as int,
      timestamp: fields[7] as DateTime,
      expedition: fields[8] as String?,
      recipientName: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Transaction obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.quantity)
      ..writeByte(3)
      ..write(obj.documentNumber)
      ..writeByte(4)
      ..write(obj.notes)
      ..writeByte(5)
      ..write(obj.previousStock)
      ..writeByte(6)
      ..write(obj.newStock)
      ..writeByte(7)
      ..write(obj.timestamp)
      ..writeByte(8)
      ..write(obj.expedition)
      ..writeByte(9)
      ..write(obj.recipientName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
