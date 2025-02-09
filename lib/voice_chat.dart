import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class VoiceChat extends StatefulWidget {
  const VoiceChat({super.key});

  @override
  State<VoiceChat> createState() => _VoiceChatState();
}

class _VoiceChatState extends State<VoiceChat> {
  // SET OPENAI API KEY
  final apiKey = dotenv.env['OPENAI_API_KEY'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Voice Chat'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'INITIAL COMMIT',
            ),
          ],
        ),
      ),
    );
  }
}
