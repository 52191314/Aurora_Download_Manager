import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/sniffer/sheets/history_sheet.dart';

void main() {
  group('HistoryTimeFilter', () {
    final now = DateTime.now();

    test('all matches any timestamp', () {
      expect(HistoryTimeFilter.all.matches(now), isTrue);
      expect(HistoryTimeFilter.all.matches(now.subtract(const Duration(days: 1))), isTrue);
      expect(HistoryTimeFilter.all.matches(now.subtract(const Duration(days: 30))), isTrue);
      expect(HistoryTimeFilter.all.matches(now.subtract(const Duration(days: 365))), isTrue);
    });

    test('today matches only same calendar day', () {
      final todayStart = DateTime(now.year, now.month, now.day, 0, 1);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59);
      final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(hours: 2));

      expect(HistoryTimeFilter.today.matches(now), isTrue);
      expect(HistoryTimeFilter.today.matches(todayStart), isTrue);
      expect(HistoryTimeFilter.today.matches(todayEnd), isTrue);
      expect(HistoryTimeFilter.today.matches(yesterday), isFalse);
    });

    test('thisWeek matches from start of week (Monday 00:00) onwards', () {
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final beforeWeek = startOfWeek.subtract(const Duration(minutes: 1));

      expect(HistoryTimeFilter.thisWeek.matches(now), isTrue);
      expect(HistoryTimeFilter.thisWeek.matches(startOfWeek), isTrue);
      expect(HistoryTimeFilter.thisWeek.matches(beforeWeek), isFalse);
    });

    test('thisMonth matches from 1st of current month onwards', () {
      final startOfMonth = DateTime(now.year, now.month, 1, 0, 0);
      final lastMonthEnd = startOfMonth.subtract(const Duration(minutes: 1));

      expect(HistoryTimeFilter.thisMonth.matches(now), isTrue);
      expect(HistoryTimeFilter.thisMonth.matches(startOfMonth), isTrue);
      expect(HistoryTimeFilter.thisMonth.matches(lastMonthEnd), isFalse);
    });
  });
}
