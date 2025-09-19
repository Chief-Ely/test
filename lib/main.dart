// lib/main.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'api.dart';
import 'prompt_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Mic -> WebSocket',
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
  final ScrollController _scrollController = ScrollController();
  final List<String> _lines = [];
  StreamSubscription<String>? _wsSub;
  StreamSubscription<Uint8List>? _micSub;
  bool _isRecording = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    // Listen to transcript stream from Api
    _wsSub = Api.transcriptStream.stream.listen((msg) {
      setState(() {
        _lines.add(msg);
      });
      // auto-scroll
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _micSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openWsPrompt() async {
    await showWsPromptDialog(context); // your prompt_dialog (connects inside)
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();

    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    if (Api.currentUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set websocket URL first')),
      );
      return;
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits, // raw PCM
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _micSub = stream.listen((bytes) {
        if (bytes.isNotEmpty) {
          Api.sendAudioChunk(Uint8List.fromList(bytes));
        }
      });

      setState(() => _isRecording = true);
      Api.transcriptStream.add('[mic] recording started');
    } catch (e) {
      Api.transcriptStream.add('[mic] start failed: $e');
    }
  }


  Future<void> _stopRecording() async {
    try {
      await _recorder.stop();
      await _micSub?.cancel();
      setState(() => _isRecording = false);
      Api.transcriptStream.add('[mic] recording stopped');
    } catch (e) {
      Api.transcriptStream.add('[mic] stop failed: $e');
    }
  }

  void listener(dynamic obj) {
    if (obj is Float32List) {
      // Convert Float32List PCM -> Int16 PCM -> Uint8List
      final buffer = Int16List(obj.length);
      for (int i = 0; i < obj.length; i++) {
        final v = (obj[i] * 32767).clamp(-32768, 32767).toInt();
        buffer[i] = v;
      }
      final bytes = Uint8List.view(buffer.buffer);
      Api.sendAudioChunk(bytes);
    }
  }

  void onError(Object e) {
    Api.transcriptStream.add('[mic] error: $e');
  }

  // This toggles recording
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  // Quick connect/disconnect button (optional)
  Future<void> _disconnectWs() async {
    Api.disconnect();
    Api.transcriptStream.add('[ws] manual disconnect');
  }

  @override
  Widget build(BuildContext context) {
    final connectedUrl = Api.currentUrl ?? '[not connected]';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Mic -> WS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Set WebSocket URL',
            onPressed: _openWsPrompt,
          ),
          IconButton(
            icon: const Icon(Icons.cancel),
            tooltip: 'Disconnect WebSocket',
            onPressed: _disconnectWs,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleRecording,
        backgroundColor: _isRecording ? Colors.red : Colors.blue,
        child: Icon(_isRecording ? Icons.mic : Icons.mic_none),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WebSocket: $connectedUrl',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _lines.length,
                  itemBuilder: (context, i) {
                    final line = _lines[i];
                    // Try to highlight JSON-partials (optional)
                    return SelectableText(line);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() => _lines.clear());
                  },
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final text = _lines.join('\n');
                    // copy to clipboard or show share UI — omitted for brevity
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Transcript copied (not implemented)'),
                      ),
                    );
                  },
                  child: const Text('Copy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
