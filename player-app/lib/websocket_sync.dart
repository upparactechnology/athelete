import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class WebSocketSyncManager {
  static WebSocket? _socket;
  static bool _isConnecting = false;
  static final Map<String, List<VoidCallback>> _listeners = {};

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

  static Future<void> connect() async {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
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

    String wsUrl;

    try {
      final uri = Uri.parse(ApiService.activeUrl);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';

      final wsUri = uri.replace(
        scheme: scheme,
        path: '/ws',
        queryParameters: {
          'token': token,
        },
      );

      wsUrl = wsUri.toString();
    } catch (e) {
      _isConnecting = false;
      debugPrint('WebSocket URL build failed: $e');
      return;
    }

    try {
      debugPrint('Connecting to authenticated WebSocket...');

      _socket = await WebSocket.connect(wsUrl)
          .timeout(const Duration(seconds: 6));

      _isConnecting = false;

      debugPrint('Authenticated WebSocket connected successfully.');

      Timer.periodic(const Duration(seconds: 25), (timer) {
        if (_socket?.readyState == WebSocket.open) {
          _socket!.add(jsonEncode({'type': 'ping'}));
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
          _reconnect();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _socket = null;
          _isConnecting = false;
          _reconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isConnecting = false;
      _socket = null;

      debugPrint('WebSocket connection failed: $e');

      _reconnect();
    }
  }

  static void _reconnect() {
    Timer(const Duration(seconds: 5), () {
      if (_listeners.isNotEmpty) {
        connect();
      }
    });
  }

  static void disconnect() {
    _socket?.close();
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
