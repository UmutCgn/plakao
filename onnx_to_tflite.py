import onnx
import onnx2tf

onnx_model_path = "Plate_detect.onnx"
output_folder = "tflite_out"

# Model giriş/çıkış şekillerini kontrol et
model = onnx.load(onnx_model_path)
for inp in model.graph.input:
    dims = [d.dim_value for d in inp.type.tensor_type.shape.dim]
    print("Input:", inp.name, dims)
for out in model.graph.output:
    dims = [d.dim_value for d in out.type.tensor_type.shape.dim]
    print("Output:", out.name, dims)

# Float32 (veya FP16) TFLite çıktısı üret
onnx2tf.convert(
    input_onnx_file_path=onnx_model_path,
    output_folder_path=output_folder,
    copy_onnx_input_output_names_to_tflite=True,
    non_verbose=True,
)