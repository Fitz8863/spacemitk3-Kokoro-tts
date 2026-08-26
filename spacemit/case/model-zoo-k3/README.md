# K3 Kokoro A100 运行案例

本目录提供可直接在 K3 板端执行的脚本：

- `run_a100.sh`：默认将 SpaceMIT EP worker 绑定到 A100 核心 `8-15`，支持 `--cores` 精确选择子集；
- `run.sh`：通用入口，可选择 SpaceMIT EP 或 CPU、具体 EP 核列表和 repeat 次数；
- `affinity.sh`：解析 `8,10`、`8-11` 等用户核列表。

详细的硬件环境、模型来源、构建步骤、性能矩阵、A100 `/proc` 绑核证据、EP/CPU fallback 边界和清理策略见仓库根目录 [`README.md`](../../../README.md)。

## 快速运行

```bash
cd spacemit/case/model-zoo-k3

./run_a100.sh zh kokoro-zh-a100.wav \
  '这是一个语音合成测试'

./run_a100.sh en kokoro-en-a100.wav \
  'This is a spacemit k3 kokoro performance test.'
```

## 交互式常驻模式

程序启动后可以连续输入文本，每行按 Enter 触发一次合成。引擎只初始化一次，后续结果始终覆盖同一个 WAV 文件：

```bash
# 默认使用 A100 8-15
./run_a100.sh zh interactive.wav --interactive

# 只绑定 A100 核 8 和 10
./run_a100.sh zh interactive.wav --interactive --cores 8,10
```

输入 `q`、`quit` 或 `exit` 退出；空行忽略，Ctrl-D 也可退出。交互模式适合单路请求，合成当前文本期间不会并行处理下一条输入。

稳态性能测试：

```bash
./run_a100.sh zh kokoro-zh-repeat3.wav \
  '这是一个语音合成测试' 3

./run_a100.sh en kokoro-en-repeat3.wav \
  'This is a spacemit k3 kokoro performance test.' 3
```

## 默认配置和选择 A100 核

```text
SPACEMIT_TTS_EP_THREADS=8
SPACEMIT_TTS_EP_CORES=8-15
SPACEMIT_TTS_EP_AFFINITY=8;9;10;11;12;13;14;15
SPACEMIT_TTS_WARMUP_RUNS=1
```

K3 上 `0-7` 是 X100，`8-15` 是 A100。可以只让部分 A100 参与 EP 计算：

```bash
# 两个不连续的 A100 核，线程数自动设置为 2
./run_a100.sh zh output-2core.wav '这是一个语音合成测试' --cores 8,10

# 四个 A100 核，重复 3 次
./run_a100.sh en output-4core.wav \
  'This is a spacemit k3 kokoro performance test.' 3 --cores 8,10,12,14

# 连续范围写法
./run_a100.sh zh output-4core-range.wav '这是一个语音合成测试' --cores 8-11
```

也可以使用环境变量：

```bash
SPACEMIT_TTS_EP_CORES=8,11 ./run_a100.sh zh output.wav '这是一个语音合成测试'
```

脚本接受逗号、范围、空格和分号分隔的列表，并自动转换为 EP 所需格式。命令行 `--cores` 优先于 `SPACEMIT_TTS_EP_CORES`，后者优先于兼容旧参数 `SPACEMIT_TTS_EP_AFFINITY`。如果手工设置 `SPACEMIT_TTS_EP_THREADS`，必须等于所选核数。

中文 ONNX 超过 GitHub 普通 Git 单文件限制。若缓存中不存在中文模型，首次运行会通过官方 Model Zoo 地址自动下载；也可以提前执行：

```bash
../../../scripts/download_models.sh
```

默认情况下脚本从板端系统目录 `/usr/local/lib`、`/usr/lib/riscv64-linux-gnu` 和 `/usr/lib` 加载 ORT/EP，不依赖某个用户的 home 路径。

如果系统尚未安装 SpaceMIT ORT/EP，可在仓库根目录执行：

```bash
../../../scripts/install_spacemit_ort.sh /path/to/spacemit-ort.riscv64.2.0.6
```

只有需要使用私有 Bundle 时才设置覆盖：

```bash
SPACEMIT_ORT_ROOT=/path/to/spacemit-ort.riscv64.2.0.6 \
  ./run_a100.sh zh output.wav '这是一个语音合成测试'
```

## 音色目录和运行时切换

仓库根目录的 `voices/en`、`voices/zh` 是独立音色目录，运行脚本会按语言自动选择对应
目录。当前已随仓库提供：英文 **54** 个音色，中文 **104** 个文件（其中 103 个来自
ModelScope 的 `Kokoro-82M-v1.1-zh`，另含原有 `zf_xiaobei` 兼容音色）。每个新导入的
style tensor 为 `[510, 1, 256]` 的 `float32`，约 522 KB。

查看板端当前实际安装的音色：

```bash
./run_a100.sh en --list-voices
./run_a100.sh zh --list-voices
```

选择音色名称：

```bash
# ModelScope 英文音色
./run_a100.sh en alloy.wav \
  'This is the Alloy voice.' \
  --voice af_alloy --cores 8,10

# ModelScope 中文音色
./run_a100.sh zh zf003.wav \
  '这是第三个中文音色。' \
  --voice zf_003 --cores 8,10

./run_a100.sh zh zm009.wav \
  '这是中文男声音色。' \
  --voice zm_009 --cores 8,10
```

交互模式启动时固定一个音色，后续每行文本都会使用该音色并覆盖同一个输出 WAV：

```bash
./run_a100.sh zh interactive.wav \
  --interactive --voice zf_003 --cores 8,10
```

也可从模型目录之外加载音色：

```bash
./run_a100.sh zh output.wav '你好' \
  --voices-dir /data/kokoro-voices/zh \
  --voice zf_003
```

外部目录中放 `<voice>.bin` 或 `<voice>.npy`。官方 `.pt` 需要先用仓库根目录的
`scripts/import_kokoro_voices.py` 转换；脚本默认优先从 ModelScope 下载，失败后回退
Hugging Face：

```bash
cd ../../..
python3 scripts/import_kokoro_voices.py --language all --keep-going
```

单文件 `--voice-path FILE` 的优先级高于目录搜索。完整导入清单见根目录
`voices/manifest.json`。
