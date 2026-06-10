import "package:flutter/material.dart";
import "package:yolo_live_stream/yolo_live_stream.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "YOLO Live Stream",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const ExampleHome(),
    );
  }
}

class ExampleHome extends StatefulWidget {
  const ExampleHome({super.key});

  @override
  State<ExampleHome> createState() => _ExampleHomeState();
}

class _ExampleHomeState extends State<ExampleHome> {
  Role role = Role.sender;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: LiveStreamRoleSwitcher(
                role: role,
                onChanged: (Role value) {
                  setState(() {
                    role = value;
                  });
                },
              ),
            ),
            Expanded(
              child: LiveStreamingView(role: role),
            ),
          ],
        ),
      ),
    );
  }
}
