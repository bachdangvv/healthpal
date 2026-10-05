import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'types.dart';

export 'types.dart';

typedef _InitC = Int32 Function();
typedef _InitDart = int Function();
typedef _JsonFnC = Pointer<Utf8> Function();
typedef _JsonFnDart = Pointer<Utf8> Function();
typedef _AssessC = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _AssessDart = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _FreeC = Void Function(Pointer<Utf8> ptr);
typedef _FreeDart = void Function(Pointer<Utf8> ptr);

DynamicLibrary? _lib;
_InitDart? _initNative;
_JsonFnDart? _modelInfoNative;
_AssessDart? _assessNative;
_FreeDart? _freeNative;
bool _initialized = false;

void _ensureLibrary() {
  if (_lib != null) return;
  final lib = _openNativeLibrary();
  _lib = lib;
  _initNative = lib.lookupFunction<_InitC, _InitDart>('healthpal_init');
  _modelInfoNative = lib.lookupFunction<_JsonFnC, _JsonFnDart>(
    'healthpal_model_info_json',
  );
  _assessNative = lib.lookupFunction<_AssessC, _AssessDart>(
    'healthpal_assess_json',
  );
  _freeNative = lib.lookupFunction<_FreeC, _FreeDart>('healthpal_free_string');
}

DynamicLibrary _openNativeLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libhealthpal_core.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('healthpal_core.dll');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  return DynamicLibrary.open('libhealthpal_core.so');
}

/// Loads the native library and ONNX session once. Safe to call from the UI
/// isolate and from a background isolate. ONNX pointers never leave Rust.
Future<void> initHealthpalRust() async {
  if (_initialized) {
    return;
  }
  _ensureLibrary();
  final code = _initNative!();
  if (code != 0) {
    throw const AssessmentException(
      kind: 'model',
      code: 'model_error',
      message: 'failed to initialize HealthPal native runtime',
    );
  }
  _initialized = true;
}

ModelInfo modelInfo() {
  _ensureInitialized();
  _ensureLibrary();
  return _readOk(_modelInfoNative!(), ModelInfo.fromNativeJson);
}

AssessmentResult assess({required AssessmentRequest request}) {
  _ensureInitialized();
  final encoded = jsonEncode(request.toNativeJson());
  final pointer = encoded.toNativeUtf8();
  try {
    _ensureLibrary();
    return _readOk(_assessNative!(pointer), AssessmentResult.fromNativeJson);
  } finally {
    malloc.free(pointer);
  }
}

void _ensureInitialized() {
  if (!_initialized) {
    throw const AssessmentException(
      kind: 'internal',
      code: 'not_initialized',
      message: 'call initHealthpalRust() before modelInfo() or assess()',
    );
  }
}

T _readOk<T>(
  Pointer<Utf8> pointer,
  T Function(Map<String, dynamic> json) parse,
) {
  if (pointer == nullptr) {
    throw const AssessmentException(
      kind: 'internal',
      code: 'internal_error',
      message: 'native function returned a null JSON pointer',
    );
  }
  try {
    final payload = jsonDecode(pointer.toDartString()) as Map<String, dynamic>;
    if (payload['ok'] == true) {
      return parse(payload['result'] as Map<String, dynamic>);
    }
    throw AssessmentException.fromNativeJson(
      payload['error'] as Map<String, dynamic>,
    );
  } finally {
    _freeNative!(pointer);
  }
}
