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
    if (!_listeners.containsKey(eventType)) {
      _listeners[eventType] = [];
    }
    _listeners[eventType]!.add(callback);
    
    // Auto-start connection if not already connected
    connect();
  }

  static void unsubscribe(String eventType, VoidCallback callback) {
    if (_listeners.containsKey(eventType)) {
      _listeners[eventType]!.remove(callback);
    }
  }

  static Future<void> connect() async {
    if (_socket != null && _socket!.readyState == WebSocket.open) return;
    if (_isConnecting) return;
    
    _isConnecting = true;
    
    // Parse ws/wss endpoint dynamically based on ApiService.activeUrl
    String wsUrl = 'ws://10.0.2.2:4000/ws';
    try {
      final uri = Uri.parse(ApiService.activeUrl);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
      wsUrl = '$scheme://${uri.host}:${uri.port}/ws';
    } catch (_) {}

    try {
      debugPrint('Connecting to WebSocket at $wsUrl ...');
      _socket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 4));
      _isConnecting = false;
      debugPrint('Real-time sync WebSocket connected successfully.');

      // Start ping loop to keep socket alive
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
              debugPrint('WebSocket sync message received: $type. Triggering listeners...');
              for (final callback in List<VoidCallback>.from(_listeners[type]!)) {
                try {
                  callback();
                } catch (e) {
                  debugPrint('Listener callback error: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('Error parsing WebSocket message: $e');
          }
        },
        onDone: () {
          debugPrint('WebSocket connection closed. Retrying...');
          _socket = null;
          _reconnect();
        },
        onError: (err) {
          debugPrint('WebSocket error: $err. Retrying...');
          _socket = null;
          _reconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isConnecting = false;
      _socket = null;
      debugPrint('WebSocket connection failed: $e. Retrying in 5 seconds...');
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
  }
}
