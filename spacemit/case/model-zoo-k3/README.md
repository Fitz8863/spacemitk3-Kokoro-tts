# K3 Kokoro A100 运行案例

本目录提供可直接在 K3 板端执行的脚本：

- `run_a100.sh`：8 个 SpaceMIT EP worker 绑定 A100 核心 `8-15`，默认 warmup 1 次；
- `run.sh`：通用入口，可选择 SpaceMIT EP 或 CPU、EP affinity 和 repeat 次数。

详细的硬件环境、模型来源、构建步骤、性能矩阵、A100 `/proc` 绑核证据、EP/CPU fallback 边界和清理策略见仓库根目录 [`README.md`](../../../README.md)。

## 快速运行

```bash
cd spacemit/case/model-zoo-k3

./run_a100.sh zh kokoro-zh-a100.wav \
  '这是一个语音合成测试'

./run_a100.sh en kokoro-en-a100.wav \
  'This is a spacemit k3 kokoro performance test.'
```

稳态性能测试：

```bash
./run_a100.sh zh kokoro-zh-repeat3.wav \
  '这是一个语音合成测试' 3

./run_a100.sh en kokoro-en-repeat3.wav \
  'This is a spacemit k3 kokoro performance test.' 3
```

## 默认配置

```text
SPACEMIT_TTS_EP_THREADS=8
SPACEMIT_TTS_EP_AFFINITY=8;9;10;11;12;13;14;15
SPACEMIT_TTS_WARMUP_RUNS=1
```

中文 ONNX 超过 GitHub 普通 Git 单文件限制。若缓存中不存在中文模型，首次运行会通过官方 Model Zoo 地址自动下载；也可以提前执行：

```bash
../../../scripts/download_models.sh
```

若 ORT 不在默认路径：

```bash
SPACEMIT_ORT_ROOT=/path/to/spacemit-ort.riscv64.2.0.6 \
  ./run_a100.sh zh output.wav '这是一个语音合成测试'
```
