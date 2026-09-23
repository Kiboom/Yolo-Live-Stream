"""Train yolo26n-pose on Ultralytics dog-pose and export models that ultralytics_yolo 0.6.x can load.

Usage:
    pip install -r tool/requirements.txt
    python3 tool/train_dog_pose.py --epochs 100 --imgsz 640 --export both
    python3 tool/train_dog_pose.py --weights best.pt --export both  # export only

Outputs (pass one as `dogPoseModelPath`):
    Android: *_w8a32.tflite (TFLite export is blocked on macOS Python 3.13+)
    iOS:     *.mlpackage.zip (Core ML export is not supported on Windows)
"""

import argparse
from pathlib import Path

from export_custom_model import export_models


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
        help="tflite export is blocked on macOS Python 3.13+; coreml is not supported on Windows",
    )
    parser.add_argument("--weights", default=None, help="trained .pt to export without training")
    args = parser.parse_args()

    from ultralytics import YOLO

    if args.weights:
        best = Path(args.weights)
    else:
        device = args.device or default_device()
        model = YOLO(args.model)
        model.train(data="dog-pose.yaml", epochs=args.epochs, imgsz=args.imgsz, device=device)
        best = Path(model.trainer.best)
        print(f"Weights: {best}")

    export_models(best, args.imgsz, args.export)


if __name__ == "__main__":
    main()
