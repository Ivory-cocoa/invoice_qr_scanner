/// API Response Model
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final String? errorCode;
  final String? errorMessage;
  
  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.errorCode,
    this.errorMessage,
  });
  
  @override
  String toString() {
    if (success) {
      return 'ApiResponse(success: true, message: $message)';
    }
    return 'ApiResponse(success: false, error: $errorCode - $errorMessage)';
  }
}
