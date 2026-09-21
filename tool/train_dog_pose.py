"""Train yolo26n-pose on Ultralytics dog-pose and export plugin-ready models.

Usage:
    pip install -r tool/requirements.txt
    python3 tool/train_dog_pose.py --epochs 100 --imgsz 640 --export both

Outputs (pass one as `dogPoseModelPath`):
    Android: *_int8.tflite (TFLite export needs Linux, see ultralytics_yolo doc/models.md)
    iOS:     *.mlpackage.zip (Core ML export needs macOS)
"""

import argparse
import shutil
from pathlib import Path


def default_device():
    import torch

    if torch.cuda.is_available():
        return "0"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--device", default=None, help="cuda index, mps or cpu (default: auto)")
    parser.add_argument("--model", default="yolo26n-pose.pt")
    parser.add_argument(
        "--export",
        choices=["tflite", "coreml", "both"],
        default="both",
        help="tflite export is blocked on macOS Python 3.13+; coreml needs macOS",
    )
    args = parser.parse_args()

    from ultralytics import YOLO

    device = args.device or default_device()
    model = YOLO(args.model)
    model.train(data="dog-pose.yaml", epochs=args.epochs, imgsz=args.imgsz, device=device)
    best = Path(model.trainer.best)

    # Mirrors ultralytics_yolo 0.6.1 official export settings (doc/models.md).
    if args.export in ("tflite", "both"):
        tflite = YOLO(best).export(format="tflite", imgsz=args.imgsz, int8=True, nms=False, end2end=False, data="dog-pose.yaml")
        print(f"Android: {tflite}")

    if args.export in ("coreml", "both"):
        mlpackage = YOLO(best).export(format="coreml", imgsz=args.imgsz, int8=True, nms=False, end2end=True)
        archive = shutil.make_archive(str(mlpackage), "zip", root_dir=Path(mlpackage).parent, base_dir=Path(mlpackage).name)
        print(f"iOS: {archive}")


if __name__ == "__main__":
    main()
