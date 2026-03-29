class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException(super.message);
}

class PaymentException extends AppException {
  const PaymentException(super.message);
}

class UnauthorizedException extends AppException {
  const UnauthorizedException(super.message);
}
