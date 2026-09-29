import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class WebSocketSyncManager {
  static WebSocket? _socket;
  static bool _isConnecting = false;
  static final Map<String, List<VoidCallback>> _listeners = {};

  // Retry + lifecycle state. The reconnect loop is bounded by exponential
  // backoff and stops entirely for logout, missing token, and auth-class
  // failures (e.g. HTTP 401 on the upgrade) so one failure mode can never
  // spin forever the way the old fixed 5s retry did.
  static Timer? _reconnectTimer;
  static Timer? _pingTimer;
  static bool _manualClose = false;
  static bool _authFailed = false;
  static int _attempt = 0;

  /// Optional hook invoked when the server rejects the upgrade with an
  /// authentication failure (HTTP 401). Not wired by default; screens can
  /// set it to route an expired/deleted session back to login.
  static VoidCallback? onAuthFailure;

  static void subscribe(String eventType, VoidCallback callback) {
    _listeners.putIfAbsent(eventType, () => []);
    _listeners[eventType]!.add(callback);
    connect();
  }

  static void unsubscribe(String eventType, VoidCallback callback) {
    final listeners = _listeners[eventType];
    if (listeners == null) return;

    listeners.remove(callback);

    if (listeners.isEmpty) {
      _listeners.remove(eventType);
    }
  }

  /// Explicit (re)connect intent: login, screen subscribe, foreground return.
  /// Clears any latched stop-flags and tries immediately.
  static Future<void> connect() async {
    _manualClose = false;
    _authFailed = false;
    await _connectInternal();
  }

  static Future<void> _connectInternal() async {
    if (_manualClose || _authFailed) return;

    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _attempt = 0;
      return;
    }

    if (_isConnecting) return;

    final token = await ApiService.getToken();

    // Do not attempt anonymous WebSocket connections.
    if (token == null || token.isEmpty) {
      debugPrint('WebSocket: no access token, waiting for authentication.');
      return;
    }

    _isConnecting = true;

    late final Uri wsUri;
    try {
      final uri = Uri.parse(ApiService.activeUrl);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';

      wsUri = uri.replace(
        scheme: scheme,
        path: '/ws',
        queryParameters: {
          'token': token,
        },
      );
      if ((wsUri.scheme != 'ws' && wsUri.scheme != 'wss') ||
          wsUri.host.isEmpty) {
        throw FormatException('Built WebSocket URL has no host: $wsUri');
      }
    } catch (e, s) {
      _isConnecting = false;
      // Programming/config error: retrying cannot help, so fail loudly once.
      debugPrint('WebSocket URL build failed (not retrying): $e');
      debugPrintStack(label: 'WebSocket URL build', stackTrace: s);
      return;
    }

    _attempt++;
    if (_attempt <= 3 || _attempt % 5 == 0) {
      debugPrint(
          'Connecting to authenticated WebSocket... (attempt $_attempt)');
    }

    try {
      _socket = await WebSocket.connect(wsUri.toString())
          .timeout(const Duration(seconds: 6));

      if (_manualClose) {
        // Logged out (or otherwise closed) while the handshake was in
        // flight: drop the fresh socket instead of resurrecting it.
        try {
          await _socket?.close();
        } catch (_) {}
        _socket = null;
        _isConnecting = false;
        _pingTimer?.cancel();
        return;
      }

      _isConnecting = false;
      _attempt = 0;

      debugPrint('Authenticated WebSocket connected successfully.');

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
        if (_manualClose) {
          timer.cancel();
          return;
        }
        if (_socket?.readyState == WebSocket.open) {
          try {
            _socket!.add(jsonEncode({'type': 'ping'}));
          } catch (e) {
            debugPrint('WebSocket ping failed: $e');
          }
        } else {
          timer.cancel();
        }
      });

      _socket!.listen(
        (data) {
          try {
            final parsed = jsonDecode(data.toString());
            final type = parsed['type'] as String?;

            if (type != null && _listeners.containsKey(type)) {
              debugPrint(
                'WebSocket event received: $type',
              );

              for (final callback
                  in List<VoidCallback>.from(_listeners[type]!)) {
                try {
                  callback();
                } catch (e) {
                  debugPrint('WebSocket listener error: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('WebSocket message parse error: $e');
          }
        },
        onDone: () {
          debugPrint('WebSocket closed.');
          _socket = null;
          _isConnecting = false;
          _pingTimer?.cancel();
          _scheduleRetry();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _socket = null;
          _isConnecting = false;
          _pingTimer?.cancel();
          _scheduleRetry();
        },
        cancelOnError: true,
      );
    } catch (e, s) {
      _isConnecting = false;
      _socket = null;
      _pingTimer?.cancel();

      if (_isAuthFailure(e)) {
        // The server rejected our identity (e.g. expired/deleted session).
        // Retrying with the same token is pointless: stop, tear down, and
        // let the app route back to login via the hook.
        _authFailed = true;
        _reconnectTimer?.cancel();
        debugPrint(
            'WebSocket authentication rejected (not retrying): $e');
        debugPrintStack(
            label: 'WebSocket auth failure', stackTrace: s);
        try {
          onAuthFailure?.call();
        } catch (hookError) {
          debugPrint('WebSocket onAuthFailure hook error: $hookError');
        }
        return;
      }

      if (_attempt == 1) {
        debugPrint('WebSocket connection failed: $e');
        debugPrintStack(
            label: 'WebSocket first failure', stackTrace: s);
      } else {
        debugPrint('WebSocket connection failed (attempt $_attempt): $e');
      }

      _scheduleRetry();
    }
  }

  /// HTTP 401 on the upgrade handshake means our token is rejected.
  /// Anything else (DNS, refused, timeout, 5xx, malformed handshake) is
  /// transient or environmental and stays on the backoff retry path.
  static bool _isAuthFailure(Object e) {
    return e is WebSocketException && e.httpStatusCode == 401;
  }

  /// 5s, 10s, 20s, 40s, then 60s. One pending timer at a time; cancelled
  /// on success, manual close, logout, and auth failure.
  static void _scheduleRetry() {
    if (_manualClose || _authFailed) return;
    if (_listeners.isEmpty) return;
    _reconnectTimer?.cancel();
    final delaySeconds = _retryDelaySeconds(_attempt);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_manualClose || _authFailed) return;
      if (_listeners.isEmpty) return;
      _connectInternal();
    });
  }

  static int _retryDelaySeconds(int attempt) {
    if (attempt < 1) return 5;
    var delay = 5 * (1 << (attempt - 1));
    if (delay > 60) delay = 60;
    return delay;
  }

  static void disconnect() {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    try {
      _socket?.close();
    } catch (e) {
      debugPrint('WebSocket close error: $e');
    }
    _socket = null;
    _isConnecting = false;
  }

  static void send(String type, Map<String, dynamic> data) {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _socket!.add(
        jsonEncode({
          'type': type,
          'data': data,
        }),
      );
    }
  }
}
