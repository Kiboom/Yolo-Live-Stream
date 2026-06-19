# yolo_live_stream 프로젝트 규칙

## Dart SDK / dot-shorthand 금지

이 플러그인은 pub 배포 호환성을 위해 `pubspec.yaml`의 SDK 하한을 `^3.9.2`로 유지한다.
dot-shorthand(`.sender`, `.RTCVideoViewObjectFitCover`처럼 enum을 약식으로 쓰는 표기)는
Dart 3.10+ 기능이라 이 SDK 하한에서는 컴파일되지 않는다.

따라서 enum은 항상 명시적으로 쓴다: `Role.sender`,
`RTCVideoViewObjectFit.RTCVideoViewObjectFitCover`, `RTCPeerConnectionState.RTCPeerConnectionStateConnected` 등.

`~/.claude/skills/flutter-guidelines/SKILL.md`는 dot-shorthand를 권장하지만,
이 프로젝트에서는 위 SDK 제약 때문에 적용하지 않는다. SDK 하한을 3.10+로 올리면 이 예외는 사라진다.
