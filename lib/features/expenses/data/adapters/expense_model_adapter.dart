import 'package:hive/hive.dart';
import '../models/expense_model.dart';

class ExpenseModelAdapter extends TypeAdapter<ExpenseModel> {
  @override
  final int typeId = 0;

  @override
  ExpenseModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExpenseModel(
      id: fields[0] as String,
      name: fields[1] as String,
      amount: (fields[2] as num).toDouble(),
      date: DateTime.fromMillisecondsSinceEpoch(fields[3] as int),
      bank: fields[4] as String,
      category: fields[5] as String,
      type: fields[6] as String,
      balance: fields[7] != null ? (fields[7] as num).toDouble() : null,
    );
  }

  @override
  void write(BinaryWriter writer, ExpenseModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.date.millisecondsSinceEpoch)
      ..writeByte(4)
      ..write(obj.bank)
      ..writeByte(5)
      ..write(obj.category)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.balance);
  }
}
