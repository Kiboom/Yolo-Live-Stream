"""Export trained Ultralytics detect or pose weights to model files that ultralytics_yolo 0.6.x can load.

Usage:
    pip install -r tool/requirements.txt
    python3 tool/export_custom_model.py --weights best.pt --export both

Outputs (pass one as the model path):
    Android: *_w8a32.tflite (TFLite export is blocked on macOS Python 3.13+)
    iOS:     *.mlpackage.zip (Core ML export is not supported on Windows)
"""

import argparse
import shutil
from pathlib import Path

# The Android plugin reads the input and output shapes by these names; other names leave them empty and loading fails.
INPUT_NAME = "images"
OUTPUT_NAME = "Identity"


def find_row_width(weights):
    """Return the end-to-end row width: box(4) + score(1) + class(1), plus x, y, visibility per pose keypoint."""
    from ultralytics import YOLO

    model = YOLO(weights)
    if model.task == "detect":
        return 6
    if model.task == "pose":
        keypoints, values = model.model.model[-1].kpt_shape
        return 6 + keypoints * values
    raise SystemExit(f"{weights} is a {model.task} model; only detect and pose models are supported")


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


def check_tflite(path, imgsz, row_width):
    import numpy as np
    from ai_edge_litert.compiled_model import CompiledModel
    from ai_edge_litert.interpreter import Interpreter

    runner = Interpreter(model_path=str(path)).get_signature_runner()
    inputs, outputs = runner.get_input_details(), runner.get_output_details()
    input_shape = inputs[INPUT_NAME]["shape"].tolist() if INPUT_NAME in inputs else []
    output_shape = outputs[OUTPUT_NAME]["shape"].tolist() if OUTPUT_NAME in outputs else []
    # The plugin only writes and reads float32, and treats [1, N, W] with W < N as end-to-end rows.
    float_io = all(d["dtype"] == np.float32 for d in [*inputs.values(), *outputs.values()])
    if (
        input_shape != [1, imgsz, imgsz, 3]
        or len(output_shape) != 3
        or output_shape[2] != row_width
        or output_shape[1] <= row_width
        or not float_io
    ):
        found = {name: (d["shape"].tolist(), np.dtype(d["dtype"]).name) for name, d in {**inputs, **outputs}.items()}
        raise SystemExit(
            f"{path} is not an end-to-end model that ultralytics_yolo can load on Android: found {found}, "
            f"expected float32 input {INPUT_NAME} [1, {imgsz}, {imgsz}, 3] "
            f"and float32 output {OUTPUT_NAME} [1, N, {row_width}] with N > {row_width}"
        )

    # Repeat the plugin's by-name lookups on the same LiteRT CompiledModel runtime; they raise if a name is missing.
    model = CompiledModel.from_file(str(path))
    signature = model.get_signature_by_index(0)["key"]
    model.create_input_buffer_by_name(signature, INPUT_NAME)
    model.create_output_buffer_by_name(signature, OUTPUT_NAME)


def export_coreml(weights, imgsz):
    from ultralytics import YOLO

    return Path(YOLO(weights).export(format="coreml", imgsz=imgsz, quantize=8, nms=False))


def check_coreml(path, imgsz, row_width):
    import coremltools as ct
    from coremltools.proto import FeatureTypes_pb2

    spec = ct.utils.load_spec(str(path))
    image = spec.description.input[0].type.imageType
    output = spec.description.output[0].type.multiArrayType
    shape = list(output.shape)
    # The iOS plugin reads the output through a Float pointer and treats [1, N, W] with W < N as end-to-end rows.
    if (
        (image.width, image.height) != (imgsz, imgsz)
        or len(shape) != 3
        or shape[2] != row_width
        or shape[1] <= row_width
        or output.dataType != FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    ):
        data_type = FeatureTypes_pb2.ArrayFeatureType.ArrayDataType.Name(output.dataType)
        raise SystemExit(
            f"{path} is not an end-to-end model that ultralytics_yolo can load on iOS: "
            f"found {image.width}x{image.height} image input and {data_type} output {shape}, "
            f"expected {imgsz}x{imgsz} image input and FLOAT32 output [1, N, {row_width}] with N > {row_width}"
        )


def export_models(weights, imgsz, export):
    row_width = find_row_width(weights)

    if export in ("tflite", "both"):
        tflite = export_tflite(weights, imgsz)
        check_tflite(tflite, imgsz, row_width)
        print(f"Android: {tflite}")

    if export in ("coreml", "both"):
        mlpackage = export_coreml(weights, imgsz)
        check_coreml(mlpackage, imgsz, row_width)
        archive = shutil.make_archive(str(mlpackage), "zip", root_dir=mlpackage.parent, base_dir=mlpackage.name)
        print(f"iOS: {archive}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--weights", required=True, help="trained .pt")
    parser.add_argument(
        "--export",
        choices=["tflite", "coreml", "both"],
        default="both",
        help="tflite export is blocked on macOS Python 3.13+; coreml is not supported on Windows",
    )
    parser.add_argument("--imgsz", type=int, default=640)
    args = parser.parse_args()
    export_models(Path(args.weights), args.imgsz, args.export)


if __name__ == "__main__":
    main()
