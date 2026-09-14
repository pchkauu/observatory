import 'package:observatory/src/feature/_common/domain/ports/observation_clock.dart';

/// Suppresses matching incident fingerprints within a bounded time window.
final class DedupePolicy {
  /// Duration for which a matching fingerprint remains suppressed.
  final Duration ttl;

  /// Maximum number of fingerprints retained in memory.
  final int maxEntries;

  /// Clock used to compare fingerprint timestamps.
  final ObservationClock clock;
  final Map<String, DateTime> _entries = {};

  /// Creates a deduplication policy.
  ///
  /// Throws [ArgumentError] when [ttl] or [maxEntries] is negative.
  DedupePolicy({required this.ttl, required this.maxEntries, required this.clock}) {
    if (ttl.isNegative || maxEntries < 0) throw ArgumentError('Dedupe limits must not be negative');
  }

  /// Returns whether an incident with [fingerprint] should be sent now.
  ///
  /// Empty fingerprints and disabled limits are always allowed.
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
        return a.value.isAfter(b.value) ? b : a;
      });
      _entries.remove(oldest.key);
    }
  }
}
