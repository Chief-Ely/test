// lib/api.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';

class Api {
  static IOWebSocketChannel? _channel;
  static final StreamController<String> transcriptStream = StreamController<String>.broadcast();
  static String? currentUrl;

  /// Normalize common http/https => ws/wss
  static String _normalizeUrl(String url) {
    url = url.trim();
    if (url.startsWith('http://')) return url.replaceFirst('http://', 'ws://');
    if (url.startsWith('https://')) return url.replaceFirst('https://', 'wss://');
    if (url.startsWith('ws://') || url.startsWith('wss://')) return url;
    return 'ws://$url';
  }

  /// Connect to the websocket. Listens and emits messages to transcriptStream.
  static Future<void> connect(String url) async {
    final wsUrl = _normalizeUrl(url);
    currentUrl = wsUrl;
    try {
      disconnect();
      _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen((message) {
        _handleMessage(message);
      }, onDone: () {
        transcriptStream.add('[ws] connection closed');
        _channel = null;
      }, onError: (err) {
        transcriptStream.add('[ws] error: $err');
        _channel = null;
      });
      transcriptStream.add('[ws] connected to $wsUrl');
    } catch (e) {
      transcriptStream.add('[ws] connect failed: $e');
      rethrow;
    }
  }

  static void disconnect() {
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  static void _handleMessage(dynamic message) {
    String text;
    if (message is String) {
      text = message;
    } else if (message is List<int>) {
      text = utf8.decode(message);
    } else {
      text = message.toString();
    }

    // Try parse JSON from Vosk-like messages: {"partial":"...", "text":"..."}
    try {
      final obj = json.decode(text);
      if (obj is Map<String, dynamic>) {
        if (obj.containsKey('text')) {
          // final chunk
          transcriptStream.add(obj['text']?.toString() ?? '');
          return;
        } else if (obj.containsKey('partial')) {
          // partial: forward it (UI will combine partial+final)
          transcriptStream.add(json.encode({'partial': obj['partial'] ?? ''}));
          return;
        }
      }
    } catch (_) {
      // not JSON, just forward
    }
    transcriptStream.add(text);
  }

  /// Send raw bytes (PCM) to server
  static void sendAudioChunk(List<int> bytes) {
    if (_channel == null) {
      transcriptStream.add('[ws] not connected, cannot send chunk');
      return;
    }
    try {
      _channel!.sink.add(Uint8List.fromList(bytes));
    } catch (e) {
      transcriptStream.add('[ws] send error: $e');
    }
  }
}
