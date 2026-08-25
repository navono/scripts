# SGLang on Thor

Thor uses CUDA compute capability SM110, while the referenced DGX Spark recipe targets SM121. Use the isolated environment at `$HOME/venvs/sglang`; it contains SGLang 0.5.18, PyTorch 2.13.0+cu130, FlashInfer 0.6.17, and sglang-kernel 0.4.6.post1. The existing vLLM environment is unchanged.

## Start and Stop

```bash
./start-sglang.sh dspark   # DSpark speculative decoding
./start-sglang.sh base     # ordinary decoding for comparison
./stop-sglang.sh
```

All launchers share port `8301`, so stop other inference services first. Logs are written to `logs/sglang-server.log`.

The deployed target is `RadixArk/Qwen3.8-27B-NVFP4-BF16-LMHead`, paired with `RadixArk/Qwen3.8-27B-DSpark`. The served model name is `qwen3.8-27b-nvfp4-bf16-lmhead`.

## Thor-Specific Requirements

Always keep `--fp4-gemm-backend flashinfer_cutlass`. SGLang's automatic FP4 selection chooses CuteDSL on SM110; the first inference test caused a GPU hang and host reboot. CUTLASS compiles native `sm_110a` kernels on the first request and then reuses `$HOME/.cache/sglang`. Initial compilation can take several minutes.

Use Triton for attention and GDN, export the CUDA 13.2 library path, and expose the unpacked Python 3.12 headers through `CPATH`; these settings are already in `start-sglang.sh`.

## Validation

The RadixArk target returned a valid OpenAI-compatible response and a valid `qwen3_coder` tool call with JSON arguments in 1.57 seconds. Using the reference repository's two-call net-decode method, DSpark reached 44.47 tokens/s on its LRUCache code probe and 19.47 tokens/s on its long-essay probe. During the code probe, draft acceptance rose to about 0.56–0.62. A shorter 256-token code request took 11.82 seconds end to end (21.7 tokens/s), demonstrating why net-decode and request-wall-time results must not be mixed.

The reference repository's 51.5 tokens/s result was measured on DGX Spark with its pinned SGLang image, Torch Compile, and the packed-FP4 `lm_head` checkpoint. The BF16-LMHead checkpoint became its default later and was not used for that historical measurement.

Do not enable Torch Compile on the current Thor stack. Its GDN Triton compile fails because a loop-carried accumulator changes from FP32 to FP64. Decode CUDA Graph is enabled; prefill CUDA Graph is disabled because it adds a large capture sweep without helping this workload.
