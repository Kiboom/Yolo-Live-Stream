import "package:flutter/material.dart";
import "package:live_camera_app/live_streaming_screen.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LiveCameraApp());
}

class LiveCameraApp extends StatelessWidget {
  const LiveCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Live Camera",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const LiveStreamingScreen(),
    );
  }
}
