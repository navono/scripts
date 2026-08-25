# SGLang on Thor

Thor uses CUDA compute capability SM110, while the referenced DGX Spark recipe targets SM121. Use the isolated environment at `$HOME/venvs/sglang`; it contains SGLang 0.5.18, PyTorch 2.13.0+cu130, FlashInfer 0.6.17, and sglang-kernel 0.4.6.post1. The existing vLLM environment is unchanged.

## Start and Stop

```bash
./start-sglang.sh dspark   # DSpark speculative decoding
./start-sglang.sh base     # ordinary decoding for comparison
./stop-sglang.sh
```

All launchers share port `8301`, so stop other inference services first. Logs are written to `logs/sglang-server.log`.

## Thor-Specific Requirements

Always keep `--fp4-gemm-backend flashinfer_cutlass`. SGLang's automatic FP4 selection chooses CuteDSL on SM110; the first inference test caused a GPU hang and host reboot. CUTLASS compiles native `sm_110a` kernels on the first request and then reuses `$HOME/.cache/sglang`. Initial compilation can take several minutes.

Use Triton for attention and GDN, export the CUDA 13.2 library path, and expose the unpacked Python 3.12 headers through `CPATH`; these settings are already in `start-sglang.sh`.

## Validation

The CUTLASS base configuration returned a valid OpenAI-compatible response and a valid `qwen3_coder` tool call. A warm-cache 256-token prose run took 30.52 seconds (about 8.4 tokens/s) without speculative decoding.

DSpark with decode CUDA Graph improved a 256-token prose run to 12.83 seconds (20.0 tokens/s) and a 256-token code run to 9.09 seconds (28.2 tokens/s). The tool-call test completed in 2.11 seconds with valid JSON arguments. The code run's draft acceptance rate was only about 0.25 because the draft targets the original RadixArk model while the deployed main model is the Huihui abliterated checkpoint. Test with `RadixArk/Qwen3.8-27B-NVFP4-BF16-LMHead` for a like-for-like comparison.

Do not enable Torch Compile on the current Thor stack. Its GDN Triton compile fails because a loop-carried accumulator changes from FP32 to FP64. Decode CUDA Graph is enabled; prefill CUDA Graph is disabled because it adds a large capture sweep without helping this workload.
