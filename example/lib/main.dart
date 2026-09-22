import "package:flutter/foundation.dart";
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
  DogRiskLevel? riskLevel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 16, right: 20),
              child: LiveStreamRoleSwitcher(
                role: role,
                onChanged: (Role value) {
                  setState(() {
                    role = value;
                  });
                },
              ),
            ),
            if (riskLevel != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("Dog risk: ${riskLevel!.name}"),
              ),
            Expanded(
              child: LiveStreamingView(
                role: role,
                // Exported by tool/train_dog_pose.py; Android needs .tflite and iOS needs .mlpackage.zip.
                dogPoseModelPath: defaultTargetPlatform == TargetPlatform.iOS
                    ? "assets/models/dog_pose.mlpackage.zip"
                    : "assets/models/dog_pose.tflite",
                enableGrowlDetection: true,
                onDogRiskAnalyzed: (DogRiskReport report) {
                  setState(() {
                    riskLevel = report.level;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
