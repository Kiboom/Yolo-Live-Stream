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
import shutil
from pathlib import Path

# dog-pose keypoints; the Android pose decoder expects end-to-end rows of box(4) + score(1) + class(1) + 24 * xyc(3).
END_TO_END_ROW = 6 + 24 * 3
# The Android plugin reads the input and output shapes by these names; other names leave them empty and loading fails.
INPUT_NAME = "images"
OUTPUT_NAME = "Identity"


def default_device():
    import torch

    if torch.cuda.is_available():
        return "0"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def export_tflite(weights, imgsz):
    import litert_torch
    import torch
    from ultralytics import YOLO

    convert = litert_torch.convert

    class PluginIO(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = litert_torch.to_channel_last_io(model, args=[0])

        def forward(self, images):
            return {OUTPUT_NAME: self.model(images)}

    # LiteRT export keeps PyTorch's [1, 3, H, W] input and names the tensors args_0 and output_0.
    # The Android predictors feed [1, H, W, 3] and look the tensors up by name.
    def convert_for_plugin(module, sample_args, **kwargs):
        sample_kwargs = {INPUT_NAME: sample_args[0].permute(0, 2, 3, 1)}
        return convert(PluginIO(module).eval(), sample_kwargs=sample_kwargs, **kwargs)

    litert_torch.convert = convert_for_plugin
    try:
        # Static int8 (quantize=8) disables the end-to-end head, so use dynamic int8 to keep end-to-end rows.
        return Path(YOLO(weights).export(format="litert", imgsz=imgsz, quantize="w8a32", nms=False))
    finally:
        litert_torch.convert = convert


def check_tflite(path, imgsz):
    from ai_edge_litert.compiled_model import CompiledModel
    from ai_edge_litert.interpreter import Interpreter

    runner = Interpreter(model_path=str(path)).get_signature_runner()
    inputs = {name: d["shape"].tolist() for name, d in runner.get_input_details().items()}
    outputs = {name: d["shape"].tolist() for name, d in runner.get_output_details().items()}
    input_shape, output_shape = inputs.get(INPUT_NAME), outputs.get(OUTPUT_NAME, [])
    if input_shape != [1, imgsz, imgsz, 3] or len(output_shape) != 3 or output_shape[2] != END_TO_END_ROW:
        raise SystemExit(
            f"{path} cannot be loaded by ultralytics_yolo on Android: inputs {inputs} (expected {INPUT_NAME} "
            f"[1, {imgsz}, {imgsz}, 3]), outputs {outputs} (expected {OUTPUT_NAME} [1, N, {END_TO_END_ROW}])"
        )

    # Repeat the plugin's by-name lookups on the same LiteRT CompiledModel runtime; they raise if a name is missing.
    model = CompiledModel.from_file(str(path))
    signature = model.get_signature_by_index(0)["key"]
    model.create_input_buffer_by_name(signature, INPUT_NAME)
    model.create_output_buffer_by_name(signature, OUTPUT_NAME)


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

    if args.export in ("tflite", "both"):
        tflite = export_tflite(best, args.imgsz)
        check_tflite(tflite, args.imgsz)
        print(f"Android: {tflite}")

    if args.export in ("coreml", "both"):
        mlpackage = YOLO(best).export(format="coreml", imgsz=args.imgsz, quantize=8, nms=False)
        archive = shutil.make_archive(str(mlpackage), "zip", root_dir=Path(mlpackage).parent, base_dir=Path(mlpackage).name)
        print(f"iOS: {archive}")


if __name__ == "__main__":
    main()
