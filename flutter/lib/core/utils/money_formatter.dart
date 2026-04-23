import 'package:intl/intl.dart';

String formatMoney(num value) {
  final formatter = NumberFormat('#,##0', 'uz_UZ');
  return formatter.format(value);
}
