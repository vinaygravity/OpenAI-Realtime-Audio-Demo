import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

// ignore: non_constant_identifier_names
final OPENAI_API_KEY = dotenv.env['OPENAI_API_KEY'];

enum ConnectionStatus {
  connected,
  disconnected,
  inProgress,
}

class VoiceStreamingPage extends StatefulWidget {
  const VoiceStreamingPage({super.key});

  @override
  State<VoiceStreamingPage> createState() => _VoiceStreamingPageState();
}

class _VoiceStreamingPageState extends State<VoiceStreamingPage> {
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  RTCDataChannel? dataChannel;

  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;

  @override
  void initState() {
    super.initState();
  }

  startStreaming() {
    setState(() {
      connectionStatus = ConnectionStatus.inProgress;
    });

    //
    //
    // Step 1: Get OpenAI Secret Key
    getOpenAISecretKey(
      onSuccess: (response) {
        String secretKey = response["client_secret"]["value"] ?? "";
        startWebRTC(secretKey);
      },
      onFailure: () {
        print("Failed Step 1 to Get OpenAI Secret Key");
        setState(() {
          connectionStatus = ConnectionStatus.disconnected;
        });
      },
    );
  }

  Future<void> getOpenAISecretKey({
    required Function(Map<String, dynamic>) onSuccess,
    required Function() onFailure,
  }) async {
    // Step 1: Get OpenAI Secret Key
    final url = Uri.parse("https://api.openai.com/v1/realtime/sessions");

    final body = jsonEncode({
      "model": "gpt-4o-realtime-preview",
      "voice": "verse",
      "instructions":
          "You are my good personal assistant who just do as I say.",
    });

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $OPENAI_API_KEY",
          "Content-Type": "application/json",
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        //print("Network request successful, response content: $jsonResponse");
        if (jsonResponse is Map<String, dynamic>) {
          onSuccess(jsonResponse);
        } else {
          onFailure();
        }
      } else {
        //print("Network request failed, status code: ${response.statusCode}, response body: ${response.body}");
        onFailure();
      }
    } catch (e) {
      print("getOpenAIWebSocketSecretKey -- fail: $e");
      onFailure();
    }
  }

  Future<void> startWebRTC(String secretKey) async {
    try {
      //
      //Step 2: Get WebRTC Peer Connection
      peerConnection = await createPeerConnection({
        'iceServers': [
          {"urls": "stun:stun.l.google.com:19302"},
          {"urls": "stun:stun.l.google.com:5349"},
          {"urls": "stun:stun1.l.google.com:3478"},
          {"urls": "stun:stun1.l.google.com:5349"},
          {"urls": "stun:stun2.l.google.com:19302"},
          {"urls": "stun:stun2.l.google.com:5349"},
          {"urls": "stun:stun3.l.google.com:3478"},
          {"urls": "stun:stun3.l.google.com:5349"},
          {"urls": "stun:stun4.l.google.com:19302"},
          {"urls": "stun:stun4.l.google.com:5349"}
        ],
      });

      if (peerConnection == null) {
        print("Failed Step 2 to initialize peer connection");
        return;
      }

      peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print("2. Peer Connection State: $state");
        // if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        //   dataChannel!.send(RTCDataChannelMessage("Hello"));
        // }
      };

      //
      //
      //Step 3: Capture microphone audio
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
        'mandatory': {
          'googNoiseSuppression': true, // Noise suppression
          'googEchoCancellation': true, // Echo cancellation
          'googAutoGainControl': true, // Auto gain control
          'minSampleRate': 16000, // Minimum sample rate (Hz)
          'maxSampleRate': 48000, // Maximum sample rate (Hz)
          'minBitrate': 32000, // Minimum bitrate (bps)
          'maxBitrate': 128000, // Maximum bitrate (bps)
        },
        'optional': [
          {
            'googHighpassFilter': true
          }, // High-pass filter, enhances voice quality
        ],
      });

      if (localStream == null) {
        print("Failed Step 3 Capture microphone audio");
        return;
      }

      localStream!.getTracks().forEach((track) {
        peerConnection!.addTrack(track, localStream!);
      });

      //
      //
      //Step 4: Create Data Channel for OpenAI events
      dataChannel = await peerConnection!
          .createDataChannel('oai-events', RTCDataChannelInit());

      if (dataChannel == null) {
        print("Failed Step 4 Create Data Channel for OpenAI events");
        return;
      }

      //
      //
      //Step 5: Create SDP Offer
      RTCSessionDescription offer = await peerConnection!.createOffer();
      await peerConnection!.setLocalDescription(offer);

      //
      //
      //Step 6: Send SDP Offer to OpenAI
      String responseSDP = await sendSDPToOpenAI(offer.sdp!, secretKey);
      if (responseSDP == '') {
        print('Failed Step 6 Send SDP Offer to OpenAI');
      }
      final remoteDescription = RTCSessionDescription(responseSDP, 'answer');
      await peerConnection!.setRemoteDescription(remoteDescription);

      //
      //
      // Callback Methods
      dataChannel!.onMessage = (message) {
        print("Received message: ${message.text}");
      };

      peerConnection?.onAddStream = (MediaStream stream) {
        print("Received remote media stream");
        // Get audio or video tracks
        var audioTracks = stream.getAudioTracks();
        // var videoTracks = stream.getVideoTracks();
        if (audioTracks.isNotEmpty) {
          print("Audio track received");
          // Can be used to play audio stream
          Helper.setSpeakerphoneOn(true);

          setState(() {
            connectionStatus = ConnectionStatus.connected;
          });
        }
      };
    } catch (error) {
      //   print("Error in streaming: $error");
      setState(() {
        connectionStatus = ConnectionStatus.disconnected;
      });
    }
  }

  Future<String> sendSDPToOpenAI(String sdp, String secretKey) async {
    try {
      final url = Uri.parse("https://api.openai.com/v1/realtime");
      final client = HttpClient();
      final request = await client.postUrl(url);

      // Set request headers
      request.headers.set("Authorization", "Bearer $secretKey");
      request.headers.set("Content-Type", "application/sdp");

      // Write request body
      request.write(sdp);

      // Send request and get response
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      print("Network request successful, response content: $responseBody");
      return responseBody;
    } catch (e) {
      print(e);
    }
    return "";
  }

  void stopStreaming() {
    localStream?.getTracks().forEach((track) => track.stop());
    localStream?.dispose();
    peerConnection?.close();
    peerConnection = null;
    dataChannel?.close();
    setState(() {
      connectionStatus = ConnectionStatus.disconnected;
    });
  }

  @override
  void dispose() {
    localStream?.dispose();
    peerConnection?.close();
    peerConnection = null;
    dataChannel?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("OpenAI Real-Time Voice")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: connectionStatus == ConnectionStatus.connected
                  ? stopStreaming
                  : connectionStatus == ConnectionStatus.disconnected
                      ? startStreaming
                      : null,
              child: connectionStatus == ConnectionStatus.inProgress
                  ? Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    )
                  : Text(connectionStatus == ConnectionStatus.connected
                      ? "Stop Streaming"
                      : "Start Streaming"),
            ),
          ],
        ),
      ),
    );
  }
}
