# Kokoro TTS v1.0 (English) — SpacemiT EP quantized

- Source: onnx-community/Kokoro-82M-v1.0-ONNX (ModelScope / HuggingFace)
- kokoro-v1.0-en.q.onnx: int8 dynamic-quantized model provided by the source repo (verified on SpacemiT EP).
- voices/*.bin: style vectors (510 x 256 f32). Backend reads voices/<name>.bin.

## Run on SpacemiT EP
Requires the EP rank-3 Resize fix + generator conv fallback (keeps conv_post/Conv and istft ConvTranspose on CPU to remove metallic noise). The K3 final validation used 8 EP workers on A100 cores 8-15; warm RTF was 0.342 on the reference sentence. See the repository root README for the complete matrix and fallback boundary.

## 独立音色目录

仓库根目录 `voices/en` 已包含 ModelScope `AI-ModelScope/Kokoro-82M` 清单中的 54 个
英文 style tensor，运行时通过案例脚本的 `--voice NAME` 选择，例如
`--voice af_alloy` 或 `--voice af_nova`。每个文件是 `[510,1,256]` 的 `float32` `.npy`。
