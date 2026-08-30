import 'package:observatory/src/feature/_common/domain/ports/observation_clock.dart';

final class DedupePolicy {
  final Duration ttl;
  final int maxEntries;
  final ObservationClock clock;
  final Map<String, DateTime> _entries = {};

  DedupePolicy({
    required this.ttl,
    required this.maxEntries,
    required this.clock,
  });

  bool allow(String fingerprint) {
    if (ttl <= Duration.zero || maxEntries < 1) {
      return true;
    }
    if (fingerprint.isEmpty) {
      return true;
    }

    final now = clock.now();
    final seenAt = _entries[fingerprint];
    if (seenAt != null && now.difference(seenAt) <= ttl) {
      return false;
    }

    _entries[fingerprint] = now;
    _evict(now);
    return true;
  }

  void _evict(DateTime now) {
    _entries.removeWhere((_, seenAt) => now.difference(seenAt) > ttl);
    while (_entries.length > maxEntries) {
      final oldest = _entries.entries.reduce((a, b) {
        return a.value.isBefore(b.value) ? a : b;
      });
      _entries.remove(oldest.key);
    }
  }
}
