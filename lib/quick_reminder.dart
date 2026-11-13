/// Conservative on-device countdown parsing. No network, account or AI required.
class QuickReminder {
  const QuickReminder(this.title, this.dueAt);
  final String title;
  final DateTime dueAt;

  static QuickReminder? parse(String input, DateTime capturedAt) {
    var text = input.toLowerCase().trim();
    const digits = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < digits.length; i++) {
      text = text.replaceAll(digits[i], '${i % 10}');
    }
    const numbers = {
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
      'ten': '10',
      'fifteen': '15',
      'twenty': '20',
      'thirty': '30',
      'sixty': '60',
      'ek': '1',
      'aik': '1',
      'do': '2',
      'teen': '3',
      'char': '4',
      'panch': '5',
      'paanch': '5',
      'das': '10',
      'ایک': '1',
      'دو': '2',
      'تین': '3',
      'چار': '4',
      'پانچ': '5',
      'دس': '10',
      'پندرہ': '15',
      'بیس': '20',
      'تیس': '30',
    };
    for (final entry in numbers.entries) {
      text = text.replaceAll(
        RegExp(
          '(?<![a-zA-Z])${entry.key}(?=\\s+(?:min|hour|hr|sec|day|ghant|din|منٹ|گھنٹ|سیکنڈ|دن))',
        ),
        entry.value,
      );
    }
    if (!RegExp(
      r'remind|alarm|notify|yaad|yad|یاد',
      caseSensitive: false,
    ).hasMatch(text)) {
      return null;
    }
    // Multiple deadlines, recurrence and work estimates need the richer review flow.
    if (RegExp(
      r'\bevery\b|\bdaily\b|\bweekly\b|\brepeat\b|روز|ہر |\btakes?\b|\bworking\b|\bsubmit|\bdue\b|\bbefore\b|پہلے|\bago\b|\bdo not\b|\bdon.t\b|\bdont\b|\bcancel\b|\bnever\b|\bunless\b|\bif\b|مت |نہیں|نہ |\bnahi\b',
    ).hasMatch(text)) {
      return null;
    }
    final duration = RegExp(
      r'(\d+(?:\.\d+)?)\s*(minutes?|mins?|minut(?:es)?|منٹ|hours?|hrs?|ghant[aeiy]*|گھنٹ[ےہ]|seconds?|secs?|سیکنڈ|days?|din|دن)(?![a-z])',
    );
    final matches = duration.allMatches(text).toList();
    if (matches.length != 1 ||
        RegExp(
          r'\bat\s+\d|\b(am|pm|tomorrow|tonight|yesterday)\b|کل',
        ).hasMatch(text)) {
      return null;
    }
    final match = matches.single;
    final before = text.substring(0, match.start);
    final after = text.substring(match.end);
    if (!RegExp(r'\b(in|after)\s*$').hasMatch(before) &&
        !RegExp(r'^\s*(?:ke\s+)?(?:baad|bad|بعد)(?:\s|$)').hasMatch(after)) {
      return null;
    }
    final value = double.tryParse(match[1]!);
    if (value == null || value <= 0) return null;
    final unit = match[2]!;
    final seconds =
        value *
        (RegExp(r'^(hour|hr|ghant|گھنٹ)').hasMatch(unit)
            ? 3600
            : RegExp(r'^(day|din|دن)').hasMatch(unit)
            ? 86400
            : RegExp(r'^(sec|سیکنڈ)').hasMatch(unit)
            ? 1
            : 60);
    if (seconds < 1 || seconds > 366 * 86400) return null;
    var title = after
        .replaceFirst(
          RegExp(r'^\s*(?:(?:ke\s+)?(?:baad|bad|بعد))?\s*(?:to\s+)?'),
          '',
        )
        .trim();
    if (title.isEmpty) {
      title = before
          .replaceAll(
            RegExp(
              r'\b(hello|hi|please|can you|remind me|remind|notify me|set an? alarm|in|after)\b',
            ),
            '',
          )
          .replaceAll(
            RegExp(
              r'مجھے|یاد|دلانا|دلا|کرنا|رکھنا|mujhe|mujhy|yaad|yad|dilana|karna|rakhna',
            ),
            '',
          )
          .trim();
    }
    title = title.replaceAll(RegExp(r'^[\s,.:;!?]+|[\s,.:;!?]+$'), '').trim();
    if (title.isEmpty) title = 'Reminder';
    return QuickReminder(
      title,
      capturedAt.add(Duration(milliseconds: (seconds * 1000).round())),
    );
  }
}
