# Kokoro TTS v1.1-zh (Chinese) — SpacemiT EP quantized

- Source: alexisStacksCode/Kokoro-1.1-zh-ONNX (base: hexgrad/Kokoro-82M-v1.1-zh)
- kokoro-v1.1-zh.q.onnx: int8 model quantized from the fp32 source with xslim (--dynq --opset 17). opset 17 is required (opset 24 breaks RandomUniformLike on onnxruntime).
- tokenizer.json / config.json: needed by the misaki v1.1 zh frontend (ZHG2P version='1.1', bopomofo + numeric tones).
- voices/zf_001.pt: original voice; zf_001.npy: numpy-converted [510,1,256] f32.

## Run on SpacemiT EP
Requires the EP rank-3 Resize fix + generator conv fallback. Frontend runs in Python (misaki 0.8.x); C++ backend does inference only. The Chinese ONNX is intentionally not stored in the GitHub repository because it is larger than 100 MB. The final K3 validation used the official package with 8 EP workers on A100 cores 8-15; warm RTF was 0.256 on the reference sentence. See the repository root README.
