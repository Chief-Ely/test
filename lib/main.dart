// lib/main.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

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
  // flutter_sound recorder
  late final FlutterSoundRecorder _recorder;

  // stream controller used by flutter_sound to push audio Food objects
  StreamController<Uint8List>? _audioController;
  StreamSubscription<Uint8List>? _audioSub;

  // UI / transcript
  final ScrollController _scrollController = ScrollController();
  final List<String> _lines = [];
  StreamSubscription<String>? _wsSub;

  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();

    // initialize recorder (open) early so "must be initialized" doesn't appear
    _openRecorder();

    // subscribe to transcript stream provided by your Api class
    _wsSub = Api.transcriptStream.stream.listen((msg) {
      setState(() => _lines.add(msg));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  Future<void> _openRecorder() async {
    try {
      await _recorder.openRecorder();
      // on some platforms you might need permission first; we'll request permission when starting
    } catch (e) {
      Api.transcriptStream.add('[mic] recorder init failed: $e');
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _audioSub?.cancel();
    _audioController?.close();
    _recorder.closeRecorder();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openWsPrompt() async {
    // This shows the existing dialog in prompt_dialog.dart which already calls Api.connect
    await showWsPromptDialog(context);
  }

  Future<void> _startRecording() async {
    // ask permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    // require websocket URL (Api.currentUrl is set by prompt dialog / Api.connect)
    if (Api.currentUrl == null) {
      // open the prompt to set URL
      await showWsPromptDialog(context);
      if (Api.currentUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please set websocket URL first')),
        );
        return;
      }
    }

    try {
      // create controller and subscription that will receive Food objects from flutter_sound
    _audioController = StreamController<Uint8List>();
    _audioSub = _audioController!.stream.listen((bytes) {
      if (bytes.isNotEmpty) {
        Api.sendAudioChunk(bytes);
      }
    }, onError: (e) {
      Api.transcriptStream.add('[mic] audio stream error: $e');
    });


      // start recorder -> send PCM16 to the stream controller sink
    await _recorder.startRecorder(
      toStream: _audioController!.sink,
      codec: Codec.pcm16, // raw PCM
      sampleRate: 16000,
      numChannels: 1,
    );


      setState(() => _isRecording = true);
      Api.transcriptStream.add('[mic] recording started');
    } catch (e) {
      Api.transcriptStream.add('[mic] start failed: $e');
      // cleanup on failure
      await _audioSub?.cancel();
      _audioSub = null;
      await _audioController?.close();
      _audioController = null;
    }
  }

  Future<void> _stopRecording() async {
    try {
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
      }
      await _audioSub?.cancel();
      _audioSub = null;
      await _audioController?.close();
      _audioController = null;

      setState(() => _isRecording = false);
      Api.transcriptStream.add('[mic] recording stopped');
    } catch (e) {
      Api.transcriptStream.add('[mic] stop failed: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

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
            Text('WebSocket: $connectedUrl', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    return SelectableText(line);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => setState(() => _lines.clear()),
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    // TODO: implement copy/share if needed
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transcript copied (not implemented)')));
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
