import 'package:observatory/src/feature/_common/domain/_barrel.dart';

final class BindUser {
  final IncidentSink _sink;

  const BindUser({
    required IncidentSink sink,
  }) : _sink = sink;

  Future<void> call({
    String? id,
    String? email,
  }) {
    return _sink.bindUser(id: id, email: email);
  }

  Future<void> clear() {
    return _sink.clearUser();
  }
}
