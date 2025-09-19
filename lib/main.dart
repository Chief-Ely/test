import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api.dart';
import 'prompt_dialog.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Live Transcription",
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  String _transcript = "";
  bool _connected = false;
  StreamSubscription? _wsSub;
  StreamSubscription? _micSub;
  bool _micOn = false;
  bool _isRecording = false;


  Future<void> _setWsUrl() async {
    final url = await askForWsUrl(context);
    if (url != null && url.isNotEmpty) {
      _api.setWsUrl(url);
      _api.connect();

      _wsSub = _api.listenTranscription()?.listen((msg) {
        setState(() {
          _transcript += "\n$msg";
        });
      });

      setState(() => _connected = true);
    }
  }

  void _disconnect() {
    _wsSub?.cancel();
    _micSub?.cancel();
    _api.close();
    setState(() {
      _connected = false;
      _micOn = false;
      _transcript = "";
    });
  }

  Future<void> _toggleMic() async {
    if (_isRecording) {
      // Stop recording
      await _micSub?.cancel();
      _micSub = null;
    } else {
      // Start recording
      Stream<Uint8List>? stream = await MicStream.microphone(
        audioSource: AudioSource.MIC,
        sampleRate: 16000,
        channelConfig: ChannelConfig.CHANNEL_IN_MONO,
        audioFormat: AudioFormat.ENCODING_PCM_16BIT,
      );

      if (stream != null) {
        _micSub = stream.listen((Uint8List data) {
          _api.sendAudioChunk(data); // ✅ send to WebSocket
        });
      }
    }

    setState(() {
      _isRecording = !_isRecording;
    });
  }



  @override
  void dispose() {
    _wsSub?.cancel();
    _micSub?.cancel();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Transcription")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _connected ? _disconnect : _setWsUrl,
              child: Text(_connected ? "Disconnect" : "Set WebSocket URL"),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_transcript),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleMic,
        backgroundColor: _micOn ? Colors.red : Colors.blue,
        child: Icon(_micOn ? Icons.stop : Icons.mic),
      ),
    );
  }
}
