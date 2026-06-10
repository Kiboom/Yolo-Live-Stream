import "dart:async";
import "dart:typed_data";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";

/// YOLO 모델 크기. 왼쪽일수록 빠르고 부정확, 오른쪽일수록 느리고 정확하다.
enum YoloModel {
  nano("yolo26n"),
  small("yolo26s"),
  medium("yolo26m"),
  large("yolo26l"),
  extraLarge("yolo26x");

  const YoloModel(this.id);

  /// ultralytics_yolo에 넘기는 모델 식별자(파일명).
  final String id;
}

/// 수신한 영상에서 주기적으로 프레임을 캡처해 YOLO 객체 탐지를 돌린다.
/// 결과(detections)는 화면이 오버레이로 그린다.
class YoloAnalyzer {
  YoloAnalyzer({
    required this.onUpdate,
    required this.getRemoteTrack,
    this.model = YoloModel.medium,
    this.customModelPath,
    this.interval = const Duration(milliseconds: 400),
  });

  final YoloModel model;

  /// 커스텀 모델 경로. 지정하면 model 대신 이 경로의 모델을 쓴다.
  ///
  /// 경로 형태
  ///  - 에셋 (ex. "assets/...")
  ///  - URL (ex. "https://...")
  ///
  /// 모델 형식
  ///  - Android .tflite
  ///  - iOS .mlpackage.zip
  ///
  /// 주의사항: 반드시 detect(task=detect) 계열 모델이어야 함
  final String? customModelPath;

  /// 분석 주기. 짧을수록 박스가 자주 갱신되지만 기기 부담이 커진다(중복 분석은 _isBusy로 방지).
  final Duration interval;
  final void Function() onUpdate;
  final MediaStreamTrack? Function() getRemoteTrack;
  late final YOLO _yolo = YOLO(modelPath: customModelPath ?? model.id, task: YOLOTask.detect);
  bool _isModelLoaded = false;
  bool _isBusy = false;
  Timer? _timer;
  List<YOLOResult> detections = [];
  String debugStatus = "대기 중"; // 화면에 띄워서 분석 상태/오류를 눈으로 확인하는 용도

  // 모델을 준비하고(첫 실행 시 자동 다운로드) 주기적 분석을 시작한다.
  Future<void> start() async {
    if (!_isModelLoaded) {
      debugStatus = "모델 로딩 중...";
      onUpdate();
      await _yolo.loadModel();
      _isModelLoaded = true;
      debugStatus = "모델 로드 완료";
      onUpdate();
    }
    _timer ??= Timer.periodic(interval, (_) => _analyzeFrame());
  }

  Future<void> _analyzeFrame() async {
    final MediaStreamTrack? track = getRemoteTrack();
    if (_isBusy) return;
    if (track == null) {
      debugStatus = "원격 트랙 없음";
      onUpdate();
      return;
    }
    _isBusy = true;
    try {
      final Uint8List frame = (await track.captureFrame()).asUint8List();
      final Map<String, dynamic> result = await _yolo.predict(frame);
      final List<dynamic> rawDetections = (result["detections"] as List?) ?? [];
      detections = rawDetections.map((item) => YOLOResult.fromMap(item as Map)).toList();
      debugStatus = "프레임 ${frame.length ~/ 1024}KB, 탐지 ${detections.length}개";
      onUpdate();
    } catch (error) {
      debugStatus = "분석 오류: $error";
      onUpdate();
    } finally {
      _isBusy = false;
    }
  }

  // 분석을 멈추고 박스를 지운다.
  void stop() {
    _timer?.cancel();
    _timer = null;
    detections = [];
    onUpdate();
  }

  Future<void> dispose() async {
    stop();
    await _yolo.dispose();
  }
}
