import 'package:observatory/src/feature/_common/domain/observation.dart';

/// Receives prepared incidents and identity updates for remote delivery.
abstract interface class IncidentSink {
  /// Sends [observation] to the configured incident service.
  Future<void> capture(Observation observation);

  /// Replaces the user identity attached to later incidents.
  Future<void> bindUser({String? id, String? email});

  /// Clears the user identity attached to later incidents.
  Future<void> clearUser();

  /// Replaces device identifiers attached to later incidents.
  Future<void> bindDevice({String? connectedDeviceId, String? platformDeviceId});

  /// Clears device identifiers attached to later incidents.
  Future<void> clearDevice();
}
