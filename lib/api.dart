import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiService {
  WebSocketChannel? _channel;
  String? _wsUrl;

  void setWsUrl(String url) {
    _wsUrl = url;
  }

  void connect() {
    if (_wsUrl == null) {
      throw Exception("WebSocket URL not set. Use setWsUrl() first.");
    }
    _channel = WebSocketChannel.connect(Uri.parse(_wsUrl!));
  }

  void sendAudioChunk(Uint8List data) {
    _channel?.sink.add(data);
  }

  Stream<dynamic>? listenTranscription() {
    return _channel?.stream;
  }

  void close() {
    _channel?.sink.close();
  }
}
