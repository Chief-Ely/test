// lib/main.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
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
      title: 'Live Transcription',
      theme: ThemeData(primarySwatch: Colors.blue),
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
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _outputController = TextEditingController();

  bool _isRecording = false;
  StreamSubscription<String>? _transcriptSub;

  @override
  void initState() {
    super.initState();
    // Subscribe to transcript stream
    _transcriptSub = Api.transcriptStream.stream.listen((msg) {
      setState(() {
        _outputController.text += "$msg\n";
      });
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // stop recording
      await _recorder.stop();
      Api.disconnect();
      setState(() => _isRecording = false);
    } else {
      // ask for WebSocket link
      await showWsPromptDialog(context);
      if (Api.currentUrl == null) return;

      if (!await _recorder.hasPermission()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission not granted")),
        );
        return;
      }

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      stream.listen((Uint8List data) {
        Api.sendAudioChunk(data);
      });

      setState(() => _isRecording = true);
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _outputController.dispose();
    _transcriptSub?.cancel();
    Api.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Transcription"),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: () async {
              await showWsPromptDialog(context);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _outputController,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: "Transcriptions",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? "Stop" : "Start"),
              onPressed: _toggleRecording,
            ),
          ],
        ),
      ),
    );
  }
}
