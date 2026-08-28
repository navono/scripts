# LLM 推理硬件横向对比: Thor / DGX Spark / RTX 4090 / RTX 5090 / RTX PRO 6000

> 数据来源与性质:
> - Thor 与 DGX Spark: NVIDIA 官方 TensorRT-Edge-LLM v0.9.0 benchmark
>   (2026-08 抓取,同运行时/同模型/NVFP4/2048 上下文,实测值)
> - 三张桌面/工作站卡: 官方基准未覆盖,解码吞吐为**带宽标定估算**
>   (LLM 解码是带宽瓶颈,以 Thor 实测为基点按带宽线性缩放;
>   实测通常为估算值的 60-80%)
> - 规格来自公开资料

## 1. 规格对比

| 项目 | Jetson AGX Thor | DGX Spark (GB10) | RTX 4090 | RTX 5090 | RTX PRO 6000 Blackwell | Apple M5 | Apple M5 Pro | Apple M5 Ultra |
|---|---|---|---|---|---|---|---|---|
| 架构 | Blackwell sm_110 | Blackwell sm_121 | Ada sm_89 | Blackwell sm_120 | Blackwell sm_120 | Apple silicon(第三代) | 同左(增强) | 同左(UltraFusion) |
| GPU 定位 | 边缘 SoC | 桌面 AI 超算 | 消费旗舰 | 消费旗舰 | 专业工作站 | 整合 SoC | 整合 SoC | 整合 SoC |
| CPU | 14 核 Neoverse-V3AE | 20 核 Arm(X925+A725) | 需配主机 | 需配主机 | 需配主机 | 10 核(4P+6E) | ~14 核 | 36 核 |
| 内存 | 128GB LPDDR5x 统一 | 128GB LPDDR5x 统一 | 24GB GDDR6X | 32GB GDDR7 | 96GB GDDR7 ECC | 最高 32GB 统一 | 最高 64GB 统一 | 最高 512GB 统一 |
| **带宽** | **273GB/s**(40-130W 可调) | **273GB/s** | 1,008GB/s | **1,792GB/s** | **1,792GB/s**(Server 版 1,597 w/ECC) | **153GB/s** | **307GB/s** | **1.2TB/s** |
| FP8/FP4 | ✓/✓ | ✓/✓ | ✗/✓ | ✓/✓ | ✓/✓ | ✗(走 MLX INT4/8) | ✗ | ✗ |
| 功耗 | 130W(MAXN) | ~240W | 450W | 575W | 600W | ~20W | ~50W | ~220W |
| 形态 | 开发套件 | 整机 | 独立卡 | 独立卡 | 独立卡 | MacBook/桌面机 | MacBook/桌面机 | Mac Studio/桌面机 |
| 参考价 | $3,499 MSRP | $3,999 MSRP | $1,599 MSRP | $1,999 MSRP | $8,565 MSRP | ~$1,000+ | ~$2,000+ | ~$5,000-9,000 |

注: M5 基础款/Pro/Ultra 带宽与内存为 Apple 官方规格(153/307GB/s;Ultra 1.2TB/s、
512GB,2026-08 Mac Studio 发布)。Apple 无 CUDA,vLLM/TRT 不可用,
推理走 MLX / llama.cpp(Metal)。

## 2. 解码吞吐(dense-27B 级 NVFP4/Q4 单并发)

| 平台 | 带宽 | 吞吐 | 数据性质 |
|---|---|---|---|
| RTX 5090 | 1,792GB/s | ~90-110 t/s | 估算 |
| RTX PRO 6000 | 1,792GB/s | ~90-110 t/s | 估算 |
| Apple M5 Ultra | **1.2TB/s** | ~45-55 t/s | 估算(Metal 效率 60-65%) |
| RTX 4090 | 1,008GB/s | ~50-60 t/s | 估算 |
| Apple M5 Pro | 307GB/s | ~11-13 t/s | 估算 |
| Jetson AGX Thor | 273GB/s | **14.5 t/s** | **实测**(TRT v0.9.0) |
| DGX Spark | 273GB/s | **12.5 t/s** | **实测**(TRT v0.9.0) |
| Apple M5 | 153GB/s | ~6 t/s | 估算 |

规律: 解码是带宽瓶颈,吞吐与带宽近似成正比;
Thor/Spark 带宽相同故接近(Thor 算力略强,+16%)。
Apple 的 Metal 推理效率低于 CUDA(约 60-65% 带宽利用率 vs NVIDIA ~70-80%)。

## 3. 预填充吞吐(dense-27B 级,算力瓶颈)

| 平台 | 吞吐 | 数据性质 |
|---|---|---|
| RTX 5090 / PRO 6000 | 数倍于 Thor(原生 FP4 张量核) | 定性 |
| RTX 4090 | 高于 Thor(FP8) | 定性 |
| Jetson AGX Thor | **4,433 t/s** | 实测 |
| DGX Spark | **1,586 t/s** | 实测 |

同源官方数据(Thor vs Spark)显示预填充差距 1.8-2.8×:
算力瓶颈下 GPU 规模差直接兑现,且模型越大差距越大。

## 4. 多模型吞吐参考(TRT v0.9.0 实测,Thor vs Spark)

| 模型(NVFP4) | Thor BS1 | Spark BS1 | Thor BS8 | Spark BS8 |
|---|---|---|---|---|
| Qwen3-8B | 44.4 | 37.4 | 252.0 | 216.8 |
| Qwen3-4B-Instruct-2507 | 73.7 | 62.6 | 349.6 | 298.4 |
| Qwen3-30B-A3B (MoE 3B 激活) | 84.8 | 73.3 | 249.6 | 214.4 |
| Nemotron-3-Nano-30B-A3B | 76.0 | 69.4 | 272.0 | 248.0 |
| Qwen3.5-27B-LLM | 14.5 | 12.5 | 95.2 | 84.8 |

MoE 小激活模型(30B-A3B)解码可达 dense 27B 的 6 倍——
激活参数少对带宽的需求天然更低。

## 5. 显存容量适配矩阵(量化后权重 + KV 需一并装入)

| 模型级别 | 权重量级 | 24G(4090) | 32G(5090/M5) | 64G(M5 Pro/5090级) | 96G(PRO 6000) | 128G(Thor/Spark) | 128-512G(M5 Ultra) |
|---|---|---|---|---|---|---|---|
| 8B Q4/NVFP4 | ~5GB | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 27B dense Q4/NVFP4 | ~16GB | ⚠️ KV 紧 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 30B-A3B MoE NVFP4 | ~17GB | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 70B Q4 | ~40GB | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| 87GB 级 Q2 MoE | 87GB | ❌ | ❌ | ❌ | ❌(+KV 超限) | ✅ | ✅ |
| ~95GB 极限量化 MoE | ~95GB | ❌ | ❌ | ❌ | ⚠️ 极限 | ✅ | ✅ |
| 70B BF16(全精度) | ~140GB | ❌ | ❌ | ❌ | ❌ | ❌(128G 不够) | ✅(256G+ 配置独有) |

Apple 的独特生态位: M5 Ultra 的大内存配置可装下**所有设备都装不下的
全精度中大型模型**(如 70B BF16),这是任何 NVIDIA 单卡/单机都做不到的;
代价是带宽档低、无 FP8/FP4、预填充弱、绑定 macOS/MLX 生态。

多卡扩展: 桌面卡可组多卡跨 PCIe,有通信损耗;统一内存设备不可扩展,
但单机即完整推理节点。

## 6. 选用逻辑

- **追求单流速度且模型 ≤32GB**: RTX 5090,带宽最高、性价比最好
- **需要 40-90GB 模型**: RTX PRO 6000(96GB)或 Thor/Spark(128GB)
- **需要 87GB+ 量化大模型**: Thor / Spark 统一内存是单机唯一解
- **需要全精度(BF16)大模型或极致安静低功耗整机**: Apple M5 Ultra
  (唯一能装 140GB+ 的单机,但速度仅为同级 NVIDIA 的一半左右)
- **长上下文/重预填充负载**: GPU 算力越大越好(桌面卡 > Thor > Spark > Apple)
- **功耗敏感部署**: Thor 能效最优(130W 提供完整 128GB 推理能力);
  Apple 整机功耗最低但速度档位也最低

## 数据来源

- Thor/Spark 性能: TensorRT-Edge-LLM v0.9.0 benchmark(2026-08 抓取)
- Apple 规格: [Mac Studio (M5 Max/Ultra) 发布](https://www.apple.com/newsroom/2026/08/apple-introduces-new-mac-studio-with-m5-max-and-m5-ultra/)、
  [MacBook Pro M5 Pro/M5 Max 技术规格](https://support.apple.com/en-us/126318)
- NVIDIA 卡规格: [RTX 4090 TechPowerUp](https://www.techpowerup.com/gpu-specs/geforce-rtx-4090.c3889)、
  [RTX 5090 官方页](https://www.nvidia.com/en-us/geforce/graphics-cards/50-series/rtx-5090/)、
  [RTX PRO 6000 Blackwell](https://www.nvidia.com/en-us/data-center/rtx-pro-6000-blackwell-server-edition/)
  (工作站版 1,792GB/s@28Gbps;Server 版 1,597GB/s 为 ECC 开启后数值)
- Thor/Spark 规格: [Jetson Thor 官方页](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-thor/)
  (128GB 256-bit LPDDR5X, 273GB/s, 40-130W);价格为 MSRP,现货市场普遍溢价
  (Spark/Thor 二手与整机溢价 1.5-2× 不等)
