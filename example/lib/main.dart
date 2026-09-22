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
  DogRiskReport? dogRiskReport;

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
                    dogRiskReport = null;
                  });
                },
              ),
            ),
            // Only the receiver analyzes video and audio, so the sender has no report to show.
            if (role == Role.receiver) _buildDogRiskPanel(),
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
                    dogRiskReport = report;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDogRiskPanel() {
    final DogRiskReport? report = dogRiskReport;
    final double? growlScore = report?.growlScore;
    final double? distance = report?.distance;
    final List<String> tensionSignals = [
      if (report?.isTailRaised == true) "꼬리 들림",
      if (report?.isHeadLoweredForward == true) "머리 낮추고 앞으로 쏠림",
    ];
    final bool hasTensionResult = report?.isTailRaised != null || report?.isHeadLoweredForward != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 20, top: 12, right: 20),
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1C1C22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "강아지 위험도",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          _buildDogRiskRow(
            "위험도",
            switch (report?.level) {
              null => "-",
              DogRiskLevel.low => "낮음",
              DogRiskLevel.caution => "주의",
              DogRiskLevel.high => "높음",
            },
          ),
          _buildDogRiskRow(
            "으르렁",
            growlScore == null
                ? "-"
                : "${growlScore.toStringAsFixed(2)}${growlScore >= const DogRiskThresholds().growlScore ? " (감지)" : ""}",
          ),
          _buildDogRiskRow("거리", distance == null ? "-" : distance.toStringAsFixed(2)),
          _buildDogRiskRow(
            "자세",
            switch (report?.posture) {
              null => "-",
              DogPosture.standing => "서 있음",
              DogPosture.sitting => "앉음",
              DogPosture.lying => "엎드림",
              DogPosture.unknown => "판정 불가",
            },
          ),
          _buildDogRiskRow(
            "시선",
            switch (report?.isFacingPerson) {
              null => "-",
              true => "사람 쪽을 봄",
              false => "다른 쪽을 봄",
            },
          ),
          _buildDogRiskRow(
            "긴장",
            !hasTensionResult ? "-" : tensionSignals.isEmpty ? "없음" : tensionSignals.join(", "),
          ),
        ],
      ),
    );
  }

  Widget _buildDogRiskRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
