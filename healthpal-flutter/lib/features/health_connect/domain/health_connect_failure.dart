enum HealthConnectFailureCode {
  unavailable,
  unsupported,
  permissionDenied,
  backgroundNotSupported,
  interrupted,
  malformedRecord,
}

class HealthConnectFailure implements Exception {
  const HealthConnectFailure(this.code, {this.message});

  final HealthConnectFailureCode code;
  final String? message;

  @override
  String toString() =>
      'HealthConnectFailure(${code.name}${message == null ? '' : ': $message'})';
}
