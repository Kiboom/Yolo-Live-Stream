import "dart:async";
import "dart:typed_data";

import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";

/// 수신한 영상에서 주기적으로 프레임을 캡처해 YOLO 객체 탐지를 돌린다.
/// 결과(detections)는 화면이 오버레이로 그린다.
class YoloAnalyzer {
  YoloAnalyzer({required this.onUpdate, required this.getRemoteTrack});

  // 모델 크기 옵션(왼쪽일수록 빠르고 부정확, 오른쪽일수록 느리고 정확):
  // yolo26n < yolo26s < yolo26m < yolo26l < yolo26x
  static const String _modelId = "yolo26m";

  // 분석 주기. 짧을수록 박스가 자주 갱신되지만 기기 부담이 커진다(중복 분석은 _isBusy로 방지).
  static const Duration _interval = Duration(milliseconds: 400);
  final void Function() onUpdate;
  final MediaStreamTrack? Function() getRemoteTrack;
  final YOLO _yolo = YOLO(modelPath: _modelId, task: YOLOTask.detect);
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
    _timer ??= Timer.periodic(_interval, (_) => _analyzeFrame());
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
