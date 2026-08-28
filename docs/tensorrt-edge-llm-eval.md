# TensorRT-Edge-LLM 评估（2026-08-28）

> 结论:**硬件完全适用(Jetson Thor = Official 支持),但当前不投入**——
> 不支持我们的主力模型 Flash-Next,且其官方公开的 27B 级性能数据
> 低于 thor 现有全部三个运行栈。列入观察名单,等 qwen4_exp 支持出现再评估。

## 仓库概况

- <https://github.com/nvidia/tensorrt-edge-llm>,Apache-2.0
- NVIDIA 官方面向边缘设备的 C++ LLM/VLM 推理运行时(Jetson/DRIVE/DGX Spark)
- 工作流: HF 权重 → ONNX → TensorRT 引擎(另有 experimental 直连构建器);
  **不消费 GGUF**
- 成熟度: v0.10.0 未到 1.0,24 commits,OpenAI server/Python API 均为 experimental,
  已知问题含 INT4/NVFP4 精度退化类 bug

## 硬件支持(对我们适用 ✅)

| 平台 | SDK | CUDA | 说明 |
|---|---|---|---|
| Jetson Thor | JetPack 7.0/7.1 | 13.0 | Official |
| Jetson Thor | JetPack 7.2 | **13.2** | Official,thor(AGX Thor/CUDA 13.2)命中此行 |
| DGX Spark (GB10) | — | 13.0 | Official |
| Jetson Orin | 6.2+ | 12.6 | 仅 FP16/INT8/INT4(Thor 无此限制,支持 NVFP4/FP8) |

功能对口: MTP/DFlash/DSpark 投机解码、KV cache 复用、NVFP4/FP8、VLM。

## 模型支持(对当前主力不适用 ❌)

| 模型 | 支持 | 备注 |
|---|---|---|
| **Qwen3.8-27B** | ✅ | v0.10.0 day-0;仅 Qwen 官方 HF 权重,设备上自行量化 |
| **Qwen3.8-Flash-Next (qwen4_exp)** | ❌ | 176B MoE + 51B n-gram 架构未跟进 |
| **DeepSeek-V4-Flash** | ❌ | 仅 DeepSeek-R1-Distill-Qwen(旧蒸馏小模型);ds4 仍是唯一引擎 |

投机解码草稿配对: DSpark 仅 qwen3-4B/8B、gemma4-12B;**27B 无任何投机解码配置**。

## 官方性能(v0.9.0,Jetson AGX Thor,NVFP4,2048 上下文)

| 模型 | BS=1 生成 | BS=8 生成 | Prefill |
|---|---|---|---|
| Qwen3.5-27B-LLM(dense 27B,3.8 的最近代理) | **14.5 t/s** | 95.2 t/s | 4,433 t/s |
| Qwen3-30B-A3B(MoE 3B 激活) | 84.8 t/s | 249.6 t/s | 14,952 t/s |
| Qwen3-8B | 44.4 t/s | 252.0 t/s | 18,897 t/s |

注: 无 Qwen3.8-27B 本尊数据(支持晚于基准发布);27B 级无投机解码行。

## 与 thor 现有 27B 栈对比

| 运行时 | 27B 解码 |
|---|---|
| TensorRT-Edge-LLM vanilla BS=1(官方) | 14.5 t/s |
| llama.cpp + DFlash2(本机) | 17.5 t/s |
| vLLM + MTP(本机) | 21.7 t/s |
| SGLang + DSpark(本机) | 44.5 t/s |

其官方数据未跑赢现有任意一栈;亮点在小激活 MoE(30B-A3B 84.8 t/s),
恰是它尚不支持的模型类别。

## 重评触发条件

1. supported-models.md 出现 **qwen4_exp / Flash-Next**(带 NVFP4 引擎工作流)
2. 出现 27B+/MoE 的**投机解码性能数据**且显著超过本机栈
3. 项目进入 1.0、OpenAI server 转正

数据来源: support-matrix.md / supported-models.md /
performance-benchmarks.md @ main(2026-08-28 抓取)。
