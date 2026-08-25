# 模型清单与来源

本仓库只直接提交能够满足 GitHub 单文件限制的英文模型文件。中文 ONNX 为 144 MB，超过 GitHub 普通 Git 单文件 100 MB 限制，因此不直接提交；运行脚本和组件会从 SpaceMIT 官方镜像自动下载。

## 官方来源

- [SpaceMIT Kokoro Model Zoo](https://archive.spacemit.com/spacemit-ai/model_zoo/tts/kokoro/)
- [SpaceMIT model-zoo-tts README](https://github.com/spacemit-com/model-zoo-tts/blob/main/README.md)

## 已提交模型

| 模型 | 文件 | 大小 | SHA-256 | 音色 |
|---|---|---:|---|---|
| Kokoro v1.0 English | `official-model-zoo/v1.0-en/kokoro-v1.0-en.q.onnx` | 83,690,161 bytes | `f515d1b02ed02af17c3892f9799f950303e41258e1a9ea762af312f85935c5e9` | `af_heart` |

英文模型的附属运行文件 `voices/af_heart.bin`、`us_gold.json` 和 `us_silver.json` 也已提交。

## 需要下载的模型

| 模型 | 压缩包 | 解压后 ONNX 大小 | SHA-256 | 压缩包 MD5 |
|---|---|---:|---|---|
| Kokoro v1.1 Chinese | `kokoro-v1.1-zh.tar.gz` | 144,349,536 bytes | `131326278b0deed1d2f8eb6df95ef8ffe63d3b70e3c024d964709ecf3bcbd36f` | `c3d93d0d6b1b0dffc32db318d2605738` |
| Kokoro v1.0 English archive | `kokoro-v1.0-en.tar.gz` | 83,690,161 bytes | `f515d1b02ed02af17c3892f9799f950303e41258e1a9ea762af312f85935c5e9` | `2ad4fb48bebdd97a0a052fa90513265e` |

中文目录中保留了 `config.json`、`tokenizer.json`、`voices/zf_001.npy` 和英文词典，便于查看目录结构；缺少 ONNX 时，首次运行会自动下载完整中文包。

校验命令：

```bash
sha256sum official-model-zoo/v1.0-en/kokoro-v1.0-en.q.onnx
sha256sum /path/to/kokoro-v1.1-zh.q.onnx
md5sum kokoro-v1.0-en.tar.gz kokoro-v1.1-zh.tar.gz
```
