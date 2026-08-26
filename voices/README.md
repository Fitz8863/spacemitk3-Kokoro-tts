# Kokoro 独立音色目录

本目录保存 SpaceMIT Kokoro 后端运行时加载的 style tensor，与 ONNX 模型包分离。

## 当前内容

- `en/`：54 个英文音色，对应 ModelScope `AI-ModelScope/Kokoro-82M` 的公开清单。
- `zh/`：103 个 `Kokoro-82M-v1.1-zh` 官方中文音色，另有仓库原有的 `zf_xiaobei`
  兼容音色，因此目录实际为 104 个文件。
- 每个 tensor 的形状为 `[510, 1, 256]`，数据类型为 little-endian `float32`。
- `.npy` 是 NumPy 文件；`.bin` 是不带头的裸 float32 文件。C++ 后端两种格式都支持。

逐文件的来源、状态和形状记录在 [`manifest.json`](manifest.json)。

## 运行时选择

```bash
cd ../spacemit/case/model-zoo-k3
./run_a100.sh en --list-voices
./run_a100.sh zh --list-voices
./run_a100.sh en output.wav 'This is an Alloy voice.' --voice af_alloy
./run_a100.sh zh output.wav '这是第三个中文音色。' --voice zf_003
```

也可以使用外部目录：

```bash
./run_a100.sh zh output.wav '你好' \\
  --voices-dir /data/kokoro-voices/zh --voice zm_009
```

## 从 ModelScope 导入

仓库根目录的导入脚本默认使用 ModelScope，单个文件下载失败后回退到 Hugging Face：

```bash
cd ..
python3 scripts/import_kokoro_voices.py --language all --keep-going
```

常用参数：

- `--language en|zh|all`：选择语言。
- `--voice NAME`：只导入指定音色，可重复指定多次。
- `--limit N`：本次最多处理 N 个音色，适合限流时分批执行。
- `--source-dir DIR`：优先从本地目录查找 `<voice>.pt`、`.npy` 或 `.bin`，可重复指定。
- `--force`：覆盖已存在的目标文件。
- `--keep-going`：单个音色失败后继续，并将失败项写入 manifest。
- `--retries N`：网络失败重试次数。

下载的 `.pt` 只是中间格式，不要直接改名为 `.npy`。脚本会解包 tensor storage、校验
最后一维为 256，并输出后端可读的 NumPy 文件。`.pt` 缓存和临时文件不应提交到仓库。
