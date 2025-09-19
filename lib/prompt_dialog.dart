import 'package:flutter/material.dart';

Future<String?> askForWsUrl(BuildContext context) async {
  final controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Enter WebSocket URL"),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          hintText: "wss://example.ngrok-free.app/live",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text("Connect"),
        ),
      ],
    ),
  );
}
