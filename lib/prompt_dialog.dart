// lib/prompt_dialog.dart
import 'package:flutter/material.dart';
import 'api.dart';

Future<void> showWsPromptDialog(BuildContext context) async {
  final controller = TextEditingController(text: Api.currentUrl ?? '');
  final formKey = GlobalKey<FormState>();

  await showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text('Set WebSocket URL'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. ws://your-ngrok-url/live or https://.../live',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter a URL';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final url = controller.text.trim();
                Navigator.of(ctx).pop();
                try {
                  await Api.connect(url);
                } catch (e) {
                  // If connect fails, show a snackbar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Connect failed: $e')),
                  );
                }
              }
            },
            child: Text('Connect'),
          ),
        ],
      );
    },
  );
}
