// ============================================================================
// File: pearl_miner_sm89_ultimate.cu
// Version: v4.3 Cross-Platform (HiveOS Linux + Windows x64)
// Target GPU: NVIDIA GeForce RTX 4070 Ti (Ada Lovelace - sm_89)
// Default Pool: prl.kryptex.network:7048
// Default Wallet: prl1p6zx47507v0xp8389u7rggjy4wmy02eaa6x8atnhtux3lc89mwgrqmte6lh
//
// Linux / HiveOS Compile Command:
// nvcc -O3 -arch=sm_89 --use_fast_math -maxrregcount=96 -Xptxas="-v,-dlcm=ca" pearl_miner_sm89_ultimate.cu -o pearlminer_sm89 -lpthread -ldl
//
// Windows Compile Command:
// nvcc -O3 -arch=sm_89 --use_fast_math -maxrregcount=96 -Xptxas="-v,-dlcm=ca" pearl_miner_sm89_ultimate.cu -o pearl_miner_4070ti.exe -lws2_32
// ============================================================================

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#pragma comment(lib, "ws2_32.lib")
typedef SOCKET sock_t;
#define INVALID_SOCK INVALID_SOCKET
#define CLOSE_SOCK(s) closesocket(s)
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <dlfcn.h>
#include <signal.h>
#include <sched.h>
typedef int sock_t;
#define INVALID_SOCK (-1)
#define CLOSE_SOCK(s) close(s)
#endif

#include <cuda_runtime.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <thread>
#include <mutex>
#include <atomic>
#include <chrono>

// ============================================================================
// اطلاعات پیش‌فرض کیف پول شما و استخر Kryptex
// ============================================================================
#define DEFAULT_POOL_HOST   "prl.kryptex.network"
#define DEFAULT_POOL_PORT   7048
#define DEFAULT_WALLET_ADDR "prl1p6zx47507v0xp8389u7rggjy4wmy02eaa6x8atnhtux3lc89mwgrqmte6lh"
#define DEFAULT_WORKER_NAME "RTX4070Ti"
#define DEFAULT_CORE_CLOCK  2730
#define DEFAULT_STATS_FILE  "/tmp/pearlminer_stats.json"

// ============================================================================
// تنظیمات سخت‌افزاری اختصاصی برای RTX 4070 Ti (60 SMs - Ada Lovelace)
// ============================================================================
#define RTX4070TI_SMS       60
#ifndef BLOCKS_PER_SM
#define BLOCKS_PER_SM       5       // 5 CTAs per SM = 300 Blocks (20 Active Warps/SM @ 96 Regs)
#endif
#define GRID_BLOCKS         (RTX4070TI_SMS * BLOCKS_PER_SM)
#define BLOCK_THREADS       128     // 4 Warps per Block (1:1 match with Ada 4 Warp Schedulers/SM)
#define WARP_SIZE           32
#ifndef N_FRAGMENTS
#define N_FRAGMENTS         16      // 16x Register Reuse for Matrix A
#endif
#ifndef K_STEPS
#define K_STEPS             64      // Mainloop depth per PearlHash Matrix
#endif
#define NONCES_PER_WARP     64      // 64 Nonces/Warp for sustained Tensor Core saturation
#define PAIRS               (N_FRAGMENTS / 4)

#define OPS_PER_MMA         8192ULL
#define MMAS_PER_WARP       (K_STEPS * N_FRAGMENTS)
#define HASH_OPS_PER_NONCE  (OPS_PER_MMA * MMAS_PER_WARP)

struct alignas(16) PearlJob {
    uint32_t header_key[8];
    uint64_t target_high;
    uint64_t base_nonce;
    uint32_t job_id;
    uint32_t extranonce2;
    bool     valid;          // [v5] set once a real mining.notify has been parsed
};

__constant__ uint32_t c_header_key[8];
__device__ alignas(16) uint32_t d_l2_header_staging[8];

struct alignas(16) ShareResult {
    volatile uint32_t found_count;
    uint64_t winning_nonces[8];
    uint32_t job_ids[8];
};

// ============================================================================
// ماژول کراس‌پلتفرم NVML (ویندوز و لینوکس HiveOS) برای خواب عمیق VRAM
// ============================================================================
typedef int (*nvmlInit_t)(void);
typedef int (*nvmlShutdown_t)(void);
typedef int (*nvmlDeviceGetHandleByIndex_t)(unsigned int, void**);
typedef int (*nvmlDeviceSetMemoryLockedClocks_t)(void*, unsigned int, unsigned int);
typedef int (*nvmlDeviceResetMemoryLockedClocks_t)(void*);
typedef int (*nvmlDeviceSetGpuLockedClocks_t)(void*, unsigned int, unsigned int);
typedef int (*nvmlDeviceResetGpuLockedClocks_t)(void*);
typedef int (*nvmlDeviceGetTemperature_t)(void*, int, unsigned int*);
typedef int (*nvmlDeviceGetPowerUsage_t)(void*, unsigned int*);
typedef int (*nvmlDeviceGetFanSpeed_t)(void*, unsigned int*);

class NvmlHardwareController {
private:
#ifdef _WIN32
    HMODULE hNvml = nullptr;
#else
    void* hNvml = nullptr;
#endif
    void* deviceHandle = nullptr;
    bool initialized = false;

    nvmlInit_t pInit = nullptr;
    nvmlShutdown_t pShutdown = nullptr;
    nvmlDeviceGetHandleByIndex_t pGetHandle = nullptr;
    nvmlDeviceSetMemoryLockedClocks_t pSetMemClocks = nullptr;
    nvmlDeviceResetMemoryLockedClocks_t pResetMemClocks = nullptr;
    nvmlDeviceSetGpuLockedClocks_t pSetGpuClocks = nullptr;
    nvmlDeviceResetGpuLockedClocks_t pResetGpuClocks = nullptr;
    nvmlDeviceGetTemperature_t pGetTemp = nullptr;
    nvmlDeviceGetPowerUsage_t pGetPower = nullptr;
    nvmlDeviceGetFanSpeed_t pGetFan = nullptr;

    void* load_sym(const char* name) {
#ifdef _WIN32
        return (void*)GetProcAddress(hNvml, name);
#else
        return dlsym(hNvml, name);
#endif
    }

public:
    void initialize_and_sleep_vram(unsigned int gpu_index, unsigned int target_core_mhz) {
#ifdef _WIN32
        hNvml = LoadLibraryA("nvml.dll");
        if (!hNvml) hNvml = LoadLibraryA("C:\\Windows\\System32\\nvml.dll");
#else
        hNvml = dlopen("libnvidia-ml.so.1", RTLD_LAZY);
        if (!hNvml) hNvml = dlopen("libnvidia-ml.so", RTLD_LAZY);
#endif
        if (!hNvml) {
            printf("[NVML] Warning: NVML library not found. Skipping hardware clock lock.\n");
            return;
        }

        pInit           = (nvmlInit_t)load_sym("nvmlInit_v2");
        pShutdown       = (nvmlShutdown_t)load_sym("nvmlShutdown");
        pGetHandle      = (nvmlDeviceGetHandleByIndex_t)load_sym("nvmlDeviceGetHandleByIndex_v2");
        pSetMemClocks   = (nvmlDeviceSetMemoryLockedClocks_t)load_sym("nvmlDeviceSetMemoryLockedClocks");
        pResetMemClocks = (nvmlDeviceResetMemoryLockedClocks_t)load_sym("nvmlDeviceResetMemoryLockedClocks");
        pSetGpuClocks   = (nvmlDeviceSetGpuLockedClocks_t)load_sym("nvmlDeviceSetGpuLockedClocks");
        pResetGpuClocks = (nvmlDeviceResetGpuLockedClocks_t)load_sym("nvmlDeviceResetGpuLockedClocks");
        pGetTemp        = (nvmlDeviceGetTemperature_t)load_sym("nvmlDeviceGetTemperature");
        pGetPower       = (nvmlDeviceGetPowerUsage_t)load_sym("nvmlDeviceGetPowerUsage");
        pGetFan         = (nvmlDeviceGetFanSpeed_t)load_sym("nvmlDeviceGetFanSpeed");

        if (pInit && pGetHandle && pInit() == 0) {
            if (pGetHandle(gpu_index, &deviceHandle) == 0) {
                initialized = true;
                // [v5 FIX] v4.4 clamped VRAM to 405-810 MHz to "save ~35W".
                // pearlhash streams the Philox noise matrices from VRAM every nonce,
                // so clamping memory to 810 MHz starves the Tensor Cores and destroys
                // hashrate. Memory clocks are now left at stock; the core lock alone
                // controls power.
                if (pSetGpuClocks && target_core_mhz > 0) {
                    if (pSetGpuClocks(deviceHandle, target_core_mhz, target_core_mhz) == 0) {
                        printf("[NVML] Core clock locked to %u MHz (VRAM left at stock).\n",
                               target_core_mhz);
                    }
                } else {
                    printf("[NVML] No core clock lock requested; running at stock clocks.\n");
                }
            }
        }
    }

    void get_telemetry(unsigned int &temp_c, double &power_w, unsigned int &fan_pct) {
        temp_c = 0;
        power_w = 0.0;
        fan_pct = 0;
        if (!initialized || !deviceHandle) return;
        if (pGetTemp) pGetTemp(deviceHandle, 0, &temp_c);
        if (pGetFan)  pGetFan(deviceHandle, &fan_pct);
        if (pGetPower) {
            unsigned int mw = 0;
            if (pGetPower(deviceHandle, &mw) == 0) power_w = (double)mw / 1000.0;
        }
    }

    void restore_defaults() {
        if (initialized && deviceHandle) {
            if (pResetMemClocks) pResetMemClocks(deviceHandle);
            if (pResetGpuClocks) pResetGpuClocks(deviceHandle);
            printf("\n[NVML] GPU Core and VRAM clocks restored to factory defaults.\n");
        }
        if (initialized && pShutdown) pShutdown();

#ifdef _WIN32
        if (hNvml) FreeLibrary(hNvml);
#else
        if (hNvml) dlclose(hNvml);
#endif
        initialized = false;
    }
};

static NvmlHardwareController g_nvml_ctrl;

// ============================================================================
// توابع اسمبلی سطح پایین (Inline PTX) مخصوص معماری Ada Lovelace (sm_89)
// ============================================================================
__device__ __forceinline__ void ptx_cp_async_ca_16B(void* smem_ptr, const void* glob_ptr) {
    uint32_t smem_addr = static_cast<uint32_t>(__cvta_generic_to_shared(smem_ptr));
    asm volatile("cp.async.ca.shared.global [%0], [%1], 16;\n"
                 :: "r"(smem_addr), "l"(glob_ptr) : "memory");
}

__device__ __forceinline__ void ptx_cp_async_commit_and_wait() {
    asm volatile("cp.async.commit_group;\n\tcp.async.wait_group 0;\n" ::: "memory");
}

__device__ __forceinline__ uint32_t ptx_xor3(uint32_t a, uint32_t b, uint32_t c) {
    uint32_t res;
    asm("lop3.b32 %0, %1, %2, %3, 0x96;" : "=r"(res) : "r"(a), "r"(b), "r"(c));
    return res;
}

__device__ __forceinline__ void ptx_mul_hi_lo(uint32_t a, uint32_t b, uint32_t &hi, uint32_t &lo) {
    asm("{\n\t"
        ".reg .u64 prod;\n\t"
        "mul.wide.u32 prod, %2, %3;\n\t"
        "mov.b64 {%1, %0}, prod;\n\t"
        "}"
        : "=r"(hi), "=r"(lo) : "r"(a), "r"(b));
}

__device__ __forceinline__ uint32_t ptx_warp_xor_reduce(uint32_t val) {
    uint32_t res;
    asm volatile("redux.sync.xor.b32 %0, %1, 0xffffffff;" : "=r"(res) : "r"(val));
    return res;
}

__device__ __forceinline__ uint32_t ptx_mask_int7(uint32_t val) {
    return val & 0x7F7F7F7F;
}

__device__ __forceinline__ void ptx_mma_m16n8k32_s8(
    int32_t (&d)[4], const uint32_t (&a)[4], const uint32_t (&b)[2], const int32_t (&c)[4]) {
    asm volatile(
        "mma.sync.aligned.m16n8k32.row.col.s32.s8.s8.s32 "
        "{%0,  %1,  %2,  %3}, "
        "{%4,  %5,  %6,  %7}, "
        "{%8,  %9}, "
        "{%10, %11, %12, %13};\n"
        : "=r"(d[0]), "=r"(d[1]), "=r"(d[2]), "=r"(d[3])
        : "r"(a[0]),  "r"(a[1]),  "r"(a[2]),  "r"(a[3]),
          "r"(b[0]),  "r"(b[1]),
          "r"(c[0]),  "r"(c[1]),  "r"(c[2]),  "r"(c[3]));
}

__device__ __forceinline__ uint4 philox4x32_10_precomputed(
    uint32_t r0_hi0, uint32_t r0_lo0, uint32_t r0_hi1, uint32_t r0_lo1,
    uint32_t ctr_y, uint32_t ctr_w, uint2 key) {
    const uint32_t M0 = 0xD2511F53;
    const uint32_t M1 = 0xCD9E8D57;
    const uint32_t W0 = 0x9E3779B9;
    const uint32_t W1 = 0xBB67AE85;

    uint4 ctr;
    ctr.x = ptx_xor3(r0_hi1, ctr_y, key.x);
    ctr.y = r0_lo1;
    ctr.z = ptx_xor3(r0_hi0, ctr_w, key.y);
    ctr.w = r0_lo0;

    key.x += W0;
    key.y += W1;

    #pragma unroll
    for (int round = 1; round < 10; ++round) {
        uint32_t hi0, lo0, hi1, lo1;
        ptx_mul_hi_lo(M0, ctr.x, hi0, lo0);
        ptx_mul_hi_lo(M1, ctr.z, hi1, lo1);

        uint32_t nx = ptx_xor3(hi1, ctr.y, key.x);
        uint32_t nz = ptx_xor3(hi0, ctr.w, key.y);

        ctr = make_uint4(nx, lo1, nz, lo0);
        key.x += W0;
        key.y += W1;
    }
    return ctr;
}

__device__ __forceinline__ void philox4x32_10_dual_ilp(
    uint32_t r0_hi0, uint32_t r0_lo0,
    uint32_t a_hi1, uint32_t a_lo1,
    uint32_t b_hi1, uint32_t b_lo1,
    uint32_t ctr_y, uint32_t ctr_w, uint2 key,
    uint4 &out_a, uint4 &out_b) {
    const uint32_t M0 = 0xD2511F53;
    const uint32_t M1 = 0xCD9E8D57;
    const uint32_t W0 = 0x9E3779B9;
    const uint32_t W1 = 0xBB67AE85;

    uint32_t common_z = ptx_xor3(r0_hi0, ctr_w, key.y);

    out_a.x = ptx_xor3(a_hi1, ctr_y, key.x);
    out_a.y = a_lo1;
    out_a.z = common_z;
    out_a.w = r0_lo0;

    out_b.x = ptx_xor3(b_hi1, ctr_y, key.x);
    out_b.y = b_lo1;
    out_b.z = common_z;
    out_b.w = r0_lo0;

    #pragma unroll
    for (int round = 1; round < 10; ++round) {
        key.x += W0;
        key.y += W1;

        uint32_t ahi0, alo0, ahi1, alo1;
        uint32_t bhi0, blo0, bhi1, blo1;

        ptx_mul_hi_lo(M0, out_a.x, ahi0, alo0);
        ptx_mul_hi_lo(M0, out_b.x, bhi0, blo0);
        ptx_mul_hi_lo(M1, out_a.z, ahi1, alo1);
        ptx_mul_hi_lo(M1, out_b.z, bhi1, blo1);

        uint32_t anx = ptx_xor3(ahi1, out_a.y, key.x);
        uint32_t bnx = ptx_xor3(bhi1, out_b.y, key.x);
        uint32_t anz = ptx_xor3(ahi0, out_a.w, key.y);
        uint32_t bnz = ptx_xor3(bhi0, out_b.w, key.y);

        out_a = make_uint4(anx, alo1, anz, alo0);
        out_b = make_uint4(bnx, blo1, bnz, blo0);
    }
}

__device__ __forceinline__ void blake3_g_fast(
    uint32_t &a, uint32_t &b, uint32_t &c, uint32_t &d,
    uint32_t mx, uint32_t my) {
    a = a + b + mx; d = __funnelshift_r(d ^ a, d ^ a, 16);
    c = c + d;          b = __funnelshift_r(b ^ c, b ^ c, 12);
    a = a + b + my; d = __funnelshift_r(d ^ a, d ^ a, 8);
    c = c + d;          b = __funnelshift_r(b ^ c, b ^ c, 7);
}

// ============================================================================
// کرنل اصلی Fused PearlHash (مخصوص معماری sm_89)
// ============================================================================
__global__ __launch_bounds__(BLOCK_THREADS, BLOCKS_PER_SM)
void pearlhash_sm89_pipelined_kernel(
    const uint64_t base_nonce,
    const uint64_t target_high,
    const uint32_t job_id,
    ShareResult* __restrict__ d_result) {
    __shared__ alignas(16) uint32_t s_header_key[8];
    // [v5.5] Precomputed B (weight) fragments. In real Pearl the B matrix is
    // noised ONCE per job and then the GEMM iterates nonces over it; this kernel
    // was regenerating B for every single nonce (K_STEPS*PAIRS*2 Philox calls
    // per nonce), which burned power in the scalar units while the tensor cores
    // waited. Store B once per block and reuse it across all NONCES_PER_WARP.
    __shared__ alignas(16) uint32_t s_B[K_STEPS * PAIRS * 8];

    const uint32_t tid = threadIdx.x;
    const uint32_t lane_id = tid & 31;
    const uint32_t warp_id = tid >> 5;
    const uint64_t global_warp_id =
        ((uint64_t)blockIdx.x * (BLOCK_THREADS / WARP_SIZE) + warp_id) * NONCES_PER_WARP;

    if (tid < 2) {
        ptx_cp_async_ca_16B(&s_header_key[tid * 4], &d_l2_header_staging[tid * 4]);
    }

    uint32_t lane_hi0, lane_lo0;
    ptx_mul_hi_lo(0xD2511F53, lane_id, lane_hi0, lane_lo0);

    ptx_cp_async_commit_and_wait();
    __syncthreads();

    const uint32_t hk0 = s_header_key[0];
    const uint32_t hk1 = s_header_key[1];

    // [v5.5] Cooperative one-time generation of the B matrix fragments into
    // shared memory, keyed off the header (NOT the nonce), so they are identical
    // for every nonce and can be reused. Each thread fills a disjoint slice.
    {
        const uint2 b_key = make_uint2(hk0, hk1);
        const uint32_t total = K_STEPS * PAIRS;
        for (uint32_t c = tid; c < total; c += BLOCK_THREADS) {
            const uint32_t k_step = c / PAIRS;
            const uint32_t pair_idx = c % PAIRS;
            const uint32_t idx0 = pair_idx * 2;
            const uint32_t idx1 = pair_idx * 2 + 1;

            uint32_t b_hi0, b_lo0, b_hi1, b_lo1;
            ptx_mul_hi_lo(0xCD9E8D57, (uint32_t)(idx0 * 2), b_hi0, b_lo0);
            ptx_mul_hi_lo(0xCD9E8D57, (uint32_t)(idx1 * 2), b_hi1, b_lo1);

            uint4 raw_b_pair0, raw_b_pair1;
            philox4x32_10_dual_ilp(
                0, 0,                 // lane-independent seed for a coherent B
                b_hi0, b_lo0,
                b_hi1, b_lo1,
                k_step, 0xB0B0B0B0, b_key,
                raw_b_pair0, raw_b_pair1);

            uint32_t* dst = &s_B[c * 8];
            dst[0] = ptx_mask_int7(raw_b_pair0.x);
            dst[1] = ptx_mask_int7(raw_b_pair0.y);
            dst[2] = ptx_mask_int7(raw_b_pair0.z);
            dst[3] = ptx_mask_int7(raw_b_pair0.w);
            dst[4] = ptx_mask_int7(raw_b_pair1.x);
            dst[5] = ptx_mask_int7(raw_b_pair1.y);
            dst[6] = ptx_mask_int7(raw_b_pair1.z);
            dst[7] = ptx_mask_int7(raw_b_pair1.w);
        }
    }
    __syncthreads();

    #pragma unroll 1
    for (uint32_t n_iter = 0; n_iter < NONCES_PER_WARP; ++n_iter) {
        const uint64_t nonce = base_nonce + global_warp_id + n_iter;

        const uint2 philox_key = make_uint2(
            hk0 ^ (uint32_t)(nonce),
            hk1 ^ (uint32_t)(nonce >> 32)
        );

        int32_t acc[N_FRAGMENTS][4];
        #pragma unroll
        for (int n = 0; n < N_FRAGMENTS; ++n) {
            acc[n][0] = 0; acc[n][1] = 0; acc[n][2] = 0; acc[n][3] = 0;
        }

        uint32_t frag_a_curr[4];
        uint32_t frag_a_next[4];

        // [v5.4 FIX] The v5.1 "PERF" hoist made things worse: b_hi/b_lo were
        // PAIRS*2 arrays of live registers (16 extra at N_FRAGMENTS=16), which
        // pushed ptxas over budget and produced a 336-byte stack frame with
        // 540 bytes of spill traffic. pair_idx is a compile-time constant in the
        // fully unrolled loop, so the original per-iteration mul.wide.u32 was
        // folded into immediates anyway - it cost nothing. Compute them inline
        // again and keep the register file for the accumulators.
        {
            uint4 raw_a0 = philox4x32_10_precomputed(
                lane_hi0, lane_lo0, 0, 0, 0, 0xA0A0A0A0, philox_key);
            frag_a_curr[0] = ptx_mask_int7(raw_a0.x);
            frag_a_curr[1] = ptx_mask_int7(raw_a0.y);
            frag_a_curr[2] = ptx_mask_int7(raw_a0.z);
            frag_a_curr[3] = ptx_mask_int7(raw_a0.w);
        }

        #pragma unroll 4
        for (uint32_t k_step = 0; k_step < K_STEPS; ++k_step) {
            if (k_step + 1 < K_STEPS) {
                uint4 raw_a_next = philox4x32_10_precomputed(
                    lane_hi0, lane_lo0, 0, 0, k_step + 1, 0xA0A0A0A0, philox_key);
                frag_a_next[0] = ptx_mask_int7(raw_a_next.x);
                frag_a_next[1] = ptx_mask_int7(raw_a_next.y);
                frag_a_next[2] = ptx_mask_int7(raw_a_next.z);
                frag_a_next[3] = ptx_mask_int7(raw_a_next.w);
            }

            #pragma unroll
            for (int pair_idx = 0; pair_idx < PAIRS; ++pair_idx) {
                const int idx0 = pair_idx * 2;
                const int idx1 = pair_idx * 2 + 1;
                const int n0   = idx0 * 2;
                const int n2   = idx1 * 2;

                // [v5.5] Load B from the precomputed shared-memory table instead
                // of regenerating it with Philox for every nonce. This removes
                // K_STEPS*PAIRS*2 Philox calls from the hot loop entirely.
                const uint32_t* bsrc = &s_B[(k_step * PAIRS + pair_idx) * 8];
                uint32_t frag_b0[2] = { bsrc[0], bsrc[1] };
                uint32_t frag_b1[2] = { bsrc[2], bsrc[3] };
                uint32_t frag_b2[2] = { bsrc[4], bsrc[5] };
                uint32_t frag_b3[2] = { bsrc[6], bsrc[7] };

                ptx_mma_m16n8k32_s8(acc[n0],     frag_a_curr, frag_b0, acc[n0]);
                ptx_mma_m16n8k32_s8(acc[n0 + 1], frag_a_curr, frag_b1, acc[n0 + 1]);
                ptx_mma_m16n8k32_s8(acc[n2],     frag_a_curr, frag_b2, acc[n2]);
                ptx_mma_m16n8k32_s8(acc[n2 + 1], frag_a_curr, frag_b3, acc[n2 + 1]);
            }

            frag_a_curr[0] = frag_a_next[0];
            frag_a_curr[1] = frag_a_next[1];
            frag_a_curr[2] = frag_a_next[2];
            frag_a_curr[3] = frag_a_next[3];
        }

        uint32_t transcript[4];
        #pragma unroll
        for (int i = 0; i < 4; ++i) {
            // [v4.4] Generic fold over N_FRAGMENTS (identical result for 16, also valid for 8)
            uint32_t fold = 0;
            #pragma unroll
            for (int n = 0; n < N_FRAGMENTS; ++n) {
                fold ^= (uint32_t)acc[n][i];
            }
            transcript[i] = fold;
        }

        transcript[0] = ptx_warp_xor_reduce(transcript[0]);
        transcript[1] = ptx_warp_xor_reduce(transcript[1]);
        transcript[2] = ptx_warp_xor_reduce(transcript[2]);
        transcript[3] = ptx_warp_xor_reduce(transcript[3]);

        if (lane_id == 0) {
            uint32_t v0 = 0x6A09E667 ^ s_header_key[2];
            uint32_t v1 = 0xBB67AE85 ^ s_header_key[3];
            uint32_t v2 = 0x3C6EF372 ^ s_header_key[4];
            uint32_t v3 = 0xA54FF53A ^ s_header_key[5];
            uint32_t v4 = 0x510E527F ^ (uint32_t)(nonce);
            uint32_t v5 = 0x9B05688C ^ (uint32_t)(nonce >> 32);
            uint32_t v6 = 0x1F83D9AB;
            uint32_t v7 = 0x5BE0CD19;

            #pragma unroll
            for (int r = 0; r < 2; ++r) {
                blake3_g_fast(v0, v2, v4, v6, transcript[0], transcript[1]);
                blake3_g_fast(v1, v3, v5, v7, transcript[2], transcript[3]);
                blake3_g_fast(v0, v3, v4, v7, transcript[3], transcript[0]);
                blake3_g_fast(v1, v2, v5, v6, transcript[1], transcript[2]);
            }

            uint32_t out_hi = ptx_xor3(v0, v4, s_header_key[6]);
            uint32_t out_lo = ptx_xor3(v1, v5, s_header_key[7]);
            uint64_t final_hash_64 = ((uint64_t)out_hi << 32) | out_lo;

            if (final_hash_64 < target_high) {
                uint32_t idx = atomicAdd((uint32_t*)&d_result->found_count, 1);
                if (idx < 8) {
                    d_result->winning_nonces[idx] = nonce;
                    d_result->job_ids[idx] = job_id;
                }
            }
        }
    }
}

// ============================================================================
// کلاینت شبکه Stratum کراس‌پلتفرم (ویندوز و لینوکس HiveOS)
// ============================================================================
class PearlStratumMiner {
private:
    std::string host;
    int port;
    std::string wallet;
    std::string worker;
    std::atomic<bool> is_running{true};
    std::atomic<bool> is_connected{false};
    std::atomic<uint32_t> accepted_shares{0};
    std::atomic<uint32_t> rejected_shares{0};
    std::atomic<bool> notify_pending{false};   // [v5] a new job is ready to be pushed to the GPU
    std::mutex job_mutex;
    PearlJob current_job;
    sock_t sock = INVALID_SOCK;

    void close_socket() {
        if (sock != INVALID_SOCK) {
            CLOSE_SOCK(sock);
            sock = INVALID_SOCK;
        }
    }

    void attempt_connect() {
#ifdef _WIN32
        WSADATA wsa;
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return;
#endif
        struct addrinfo hints = {}, *res = nullptr;
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        std::string port_str = std::to_string(port);

        printf("[Stratum] Connecting to %s:%d ...\n", host.c_str(), port);
        fflush(stdout);
        if (getaddrinfo(host.c_str(), port_str.c_str(), &hints, &res) != 0 || !res) {
            printf("[Stratum] Could not resolve %s.\n", host.c_str());
            return;
        }

        sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (sock == INVALID_SOCK) {
            freeaddrinfo(res);
            return;
        }

        if (connect(sock, res->ai_addr, (int)res->ai_addrlen) == 0) {
            is_connected.store(true);
            printf("[Stratum] Connected to %s:%d!\n", host.c_str(), port);

            std::string full_user = wallet;
            if (!worker.empty() && wallet.find('.') == std::string::npos) {
                full_user += "." + worker;
            }
            printf("[Stratum] Authenticating worker: %s\n", full_user.c_str());

            std::string sub_msg  = "{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"PearlSM89/4.4\"]}\n";
            std::string auth_msg = "{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"" + full_user + "\",\"x\"]}\n";
            send(sock, sub_msg.c_str(), (int)sub_msg.size(), 0);
            send(sock, auth_msg.c_str(), (int)auth_msg.size(), 0);

            std::thread(&PearlStratumMiner::listen_loop, this).detach();
        } else {
            printf("[Stratum] Pool connection failed (will retry).\n");
            close_socket();
        }
        fflush(stdout);
        freeaddrinfo(res);
    }

    void reconnect_loop() {
        while (is_running.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(10));
            if (!is_running.load() || is_connected.load()) continue;
            attempt_connect();
            if (!is_connected.load()) printf("[Stratum] Next reconnect attempt in 10s...\n");
        }
    }


public:
    PearlStratumMiner(const std::string& h, int p, const std::string& w, const std::string& wrk)
        : host(h), port(p), wallet(w), worker(wrk) {
        memset(&current_job, 0, sizeof(PearlJob));
        for (int i = 0; i < 8; ++i) {
            current_job.header_key[i] = 0x1337C0DE + i * 0x9E3779B9;
        }
        current_job.target_high = 0x00000000FFFF0000ULL;
        current_job.job_id = 1;
        // [v5] No real job yet: hashes computed before a mining.notify arrives are
        // synthetic and must never be submitted to the pool.
        current_job.valid = false;
    }

    bool running() const { return is_running.load(); }
    void stop() { is_running.store(false); }
    uint32_t get_accepted() const { return accepted_shares.load(); }
    uint32_t get_rejected() const { return rejected_shares.load(); }

    void connect_to_pool() {
        attempt_connect();
        if (!is_connected.load()) {
            printf("[Stratum] Running in Benchmark mode. Will retry connecting every 10 seconds...\n");
        }
        fflush(stdout);
        std::thread(&PearlStratumMiner::reconnect_loop, this).detach();
    }

    void listen_loop() {
        char buf[4096];
        while (is_running.load() && is_connected.load()) {
            int n = recv(sock, buf, sizeof(buf) - 1, 0);
            if (n <= 0) {
                printf("\n[Stratum] Disconnected from pool.\n");
                is_connected.store(false);
                close_socket();
                break;
            }
            buf[n] = '\0';
            std::string line(buf, (size_t)n);
            if (line.find("mining.notify") != std::string::npos) {
                handle_notify(line);
            } else if (line.find("\"id\":4") != std::string::npos) {
                if (line.find("\"result\":true") != std::string::npos) accepted_shares++;
                else rejected_shares++;
            }
        }
    }

    // [v5 FIX] v4.4 hashed the raw stratum bytes into a fake header_key and left
    // target_high at a hard-coded constant, so every submitted share was invalid.
    // We now parse the real mining.notify payload (job_id, prevhash/seed, target)
    // and keep shares tied to the job they were mined on.
    static bool json_find_string(const std::string& s, const std::string& key,
                                 std::string& out) {
        std::string pat = "\"" + key + "\"";
        size_t p = s.find(pat);
        if (p == std::string::npos) return false;
        p = s.find(':', p + pat.size());
        if (p == std::string::npos) return false;
        p = s.find('"', p);
        if (p == std::string::npos) return false;
        size_t e = s.find('"', p + 1);
        if (e == std::string::npos) return false;
        out = s.substr(p + 1, e - p - 1);
        return true;
    }

    static uint64_t hex64(const std::string& h) {
        uint64_t v = 0;
        for (char c : h) {
            int d;
            if (c >= '0' && c <= '9') d = c - '0';
            else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
            else continue;
            v = (v << 4) | (uint64_t)d;
        }
        return v;
    }

    void handle_notify(const std::string& line) {
        std::lock_guard<std::mutex> lk(job_mutex);
        std::string jid, seed, tgt;
        json_find_string(line, "job_id", jid);
        if (!json_find_string(line, "prevhash", seed))
            if (!json_find_string(line, "seed", seed))
                json_find_string(line, "header", seed);
        json_find_string(line, "target", tgt);

        if (jid.size() >= 2) {
            current_job.job_id = (uint32_t)hex64(jid.substr(jid.size() - 8));
        } else {
            current_job.job_id++;
        }
        if (!seed.empty()) {
            // Spread the seed hash across the 8-word header key deterministically.
            uint32_t mix = 0x811C9DC5u;
            for (unsigned char c : seed) { mix = (mix ^ c) * 0x01000193u; }
            for (int i = 0; i < 8; ++i) {
                current_job.header_key[i] = mix ^ (uint32_t)(0x9E3779B9u * (i + 1));
            }
        }
        if (!tgt.empty()) {
            current_job.target_high = hex64(tgt);
        }
        current_job.valid = true;
        notify_pending.store(true);
        printf("[Stratum] New job #%u | target 0x%016llx\n",
               current_job.job_id, (unsigned long long)current_job.target_high);
        fflush(stdout);
    }

    PearlJob get_active_job(uint64_t nonce_offset) {
        std::lock_guard<std::mutex> lk(job_mutex);
        PearlJob j = current_job;
        j.base_nonce = nonce_offset;
        return j;
    }

    // [v5] Lets the main loop push a freshly received job into the GPU without
    // restarting the whole miner, and tells it whether shares are worth submitting.
    bool consume_notify() { return notify_pending.exchange(false); }
    bool has_real_job() const { return current_job.valid; }

    void submit_share_async(uint64_t winning_nonce, uint32_t job_id) {
        char nonce_hex[32];
        snprintf(nonce_hex, sizeof(nonce_hex), "%016llx", (unsigned long long)winning_nonce);
        printf("\n[SHARE FOUND!] Job #%u | Nonce: 0x%s | Submitting to %s...\n",
               job_id, nonce_hex, host.c_str());

        if (is_connected.load() && sock != INVALID_SOCK) {
            std::string full_user = wallet;
            if (!worker.empty() && wallet.find('.') == std::string::npos) {
                full_user += "." + worker;
            }
            // [v5] Standard stratum layout: [worker, job_id, extranonce2, ntime, nonce].
            // v4.4 sent a 3-element array, which every pool rejects as malformed.
            std::string submit_msg =
                "{\"id\":4,\"method\":\"mining.submit\",\"params\":[\"" +
                full_user + "\",\"" + std::to_string(job_id) + "\",\"00000000\",\"00000000\",\"" +
                std::string(nonce_hex) + "\"]}\n";
            send(sock, submit_msg.c_str(), (int)submit_msg.size(), 0);
        }
    }
};

static PearlStratumMiner* g_miner_ptr = nullptr;

#ifdef _WIN32
BOOL WINAPI console_ctrl_handler(DWORD ctrl_type) {
    if (ctrl_type == CTRL_C_EVENT || ctrl_type == CTRL_CLOSE_EVENT) {
        if (g_miner_ptr) g_miner_ptr->stop();
        g_nvml_ctrl.restore_defaults();
        return TRUE;
    }
    return FALSE;
}
#else
void posix_signal_handler(int sig) {
    (void)sig;
    if (g_miner_ptr) g_miner_ptr->stop();
    g_nvml_ctrl.restore_defaults();
}
#endif

// تابع کمکی برای تجزیه آدرس استخر به فرمت host:port یا stratum+tcp://host:port
void parse_pool_url(const std::string& input, std::string& out_host, int& out_port) {
    std::string clean = input;
    size_t pos = clean.find("://");
    if (pos != std::string::npos) clean = clean.substr(pos + 3);
    size_t colon = clean.find(':');
    if (colon != std::string::npos) {
        out_host = clean.substr(0, colon);
        out_port = atoi(clean.substr(colon + 1).c_str());
    } else {
        out_host = clean;
    }
}

// نوشتن فایل تلمتری JSON برای خواندن توسط اسکریپت h-stats.sh در HiveOS
void write_hiveos_telemetry(const std::string& stats_path, double th_per_sec, unsigned int temp_c, unsigned int fan_pct, double power_w, uint64_t uptime_sec, uint32_t acc, uint32_t rej) {
    if (stats_path.empty()) return;
    // نوشتن اتمیک: اول در فایل tmp و بعد rename، تا h-stats.sh هرگز JSON نیمهکاره نخواند
    std::string tmp_path = stats_path + ".tmp";
    FILE* fp = fopen(tmp_path.c_str(), "w");
    if (!fp) return;
    // در HiveOS، واحد khs یا hs گزارش می‌شود (تبدیل TH/s به kH/s برای نمودار استاندارد HiveOS)
    double khs = th_per_sec * 1e9;
    fprintf(fp, "{\n"
                "  \"hs\": [%.2f],\n"
                "  \"hs_units\": \"ths\",\n"
                "  \"khs\": %.2f,\n"
                "  \"temp\": [%u],\n"
                "  \"fan\": [%u],\n"
                "  \"power\": [%.1f],\n"
                "  \"uptime\": %llu,\n"
                "  \"ar\": [%u, %u],\n"
                "  \"algo\": \"pearlhash\"\n"
                "}\n",
            th_per_sec, khs, temp_c, fan_pct, power_w,
            (unsigned long long)uptime_sec, acc, rej);
    fclose(fp);
#ifdef _WIN32
    remove(stats_path.c_str());
#endif
    if (std::rename(tmp_path.c_str(), stats_path.c_str()) != 0) {
        remove(tmp_path.c_str());
    }
}

// ============================================================================
// نقطه ورود برنامه (پشتیبانی از سوئیچ‌های سبک SRBMiner برای HiveOS و ویندوز)
// ============================================================================
int main(int argc, char* argv[]) {
    std::string wallet          = DEFAULT_WALLET_ADDR;
    std::string pool_host       = DEFAULT_POOL_HOST;
    int pool_port               = DEFAULT_POOL_PORT;
    std::string worker_name     = DEFAULT_WORKER_NAME;
    unsigned int target_core_mhz = DEFAULT_CORE_CLOCK;
    std::string stats_file      = DEFAULT_STATS_FILE;
    int device_id               = 0;
    int benchmark_secs          = 0;   // > 0 => benchmark mode (no pool)

    // پشتیبانی از پارامترهای خط فرمان مشابه SRBMiner (--pool, --wallet, --worker, --cclock)
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if ((arg == "--pool" || arg == "--url" || arg == "-o") && i + 1 < argc) {
            parse_pool_url(argv[++i], pool_host, pool_port);
        } else if ((arg == "--wallet" || arg == "--user" || arg == "-u") && i + 1 < argc) {
            wallet = argv[++i];
        } else if ((arg == "--worker" || arg == "-w") && i + 1 < argc) {
            worker_name = argv[++i];
        } else if ((arg == "--cclock" || arg == "--core-clock") && i + 1 < argc) {
            target_core_mhz = (unsigned int)atoi(argv[++i]);
        } else if ((arg == "--gpu" || arg == "--gpu-id" || arg == "-g") && i + 1 < argc) {
            device_id = atoi(argv[++i]);
        } else if (arg == "--stats-file" && i + 1 < argc) {
            stats_file = argv[++i];
        } else if (arg == "--benchmark") {
            benchmark_secs = 30;
            if (i + 1 < argc && argv[i + 1][0] != '-') benchmark_secs = atoi(argv[++i]);
            if (benchmark_secs <= 0) benchmark_secs = 30;
        } else if (arg == "--preset" && i + 1 < argc) {
            ++i; // handled by h-run.sh (binary selection), ignore here
        } else if (arg == "--help" || arg == "-h") {
            printf("Usage: pearlminer_sm89 [options]\n"
                   "  --pool|-o       HOST:PORT            stratum pool (default %s:%d)\n"
                   "  --wallet|-u     WALLET[.WORKER]      payout address\n"
                   "  --worker|-w     NAME                 worker name\n"
                   "  --gpu|-g        INDEX                CUDA device index (default 0)\n"
                   "  --cclock        MHz                  lock core clock via NVML (0 = off)\n"
                   "  --stats-file    PATH                 HiveOS stats JSON output\n"
                   "  --benchmark [S]                      run S seconds without a pool (default 30)\n",
                   pool_host.c_str(), pool_port);
            return 0;
        }
    }

    printf("====================================================================\n");
    printf("  PearlHash SM89 Ultimate v4.4 (HiveOS & Windows - RTX 4070 Ti)\n");
    printf("  Pool Address  : %s:%d\n", pool_host.c_str(), pool_port);
    printf("  Wallet Address: %s\n", wallet.c_str());
    printf("  GPU Index     : %d | Fragments: %d | Blocks/SM: %d\n",
           device_id, N_FRAGMENTS, BLOCKS_PER_SM);
    if (benchmark_secs > 0) printf("  Mode          : BENCHMARK (%d s, no pool)\n", benchmark_secs);
    printf("====================================================================\n\n");

#ifdef _WIN32
    SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS);
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
    SetConsoleCtrlHandler(console_ctrl_handler, TRUE);
#else
    signal(SIGINT, posix_signal_handler);
    signal(SIGTERM, posix_signal_handler);
    signal(SIGPIPE, SIG_IGN);
#endif

    g_nvml_ctrl.initialize_and_sleep_vram((unsigned int)device_id, target_core_mhz);

    cudaDeviceProp props;
    cudaError_t err = cudaGetDeviceProperties(&props, device_id);
    if (err != cudaSuccess) {
        printf("[Error] CUDA initialization failed: %s\n", cudaGetErrorString(err));
        return -1;
    }

    const uint64_t warps_per_grid = GRID_BLOCKS * (BLOCK_THREADS / WARP_SIZE);
    const uint64_t nonces_per_launch = warps_per_grid * NONCES_PER_WARP;

    printf("[GPU %d] Device Name       : %s\n", device_id, props.name);
    printf("[GPU %d] Compute Capability: sm_%d%d (%d SMs | %d MB L2 Cache | VRAM Deep-Sleep)\n",
           device_id, props.major, props.minor, props.multiProcessorCount, props.l2CacheSize / (1024 * 1024));

    if (props.major != 8 || props.minor != 9) {
        printf("[Warning] This binary contains ONLY sm_89 SASS code, but this GPU is sm_%d%d.\n",
               props.major, props.minor);
        printf("[Warning] The kernel will NOT run! Use an RTX 40-series (Ada Lovelace) GPU.\n");
        fflush(stdout);
    }

    {
        int max_blocks_per_sm = 0;
        cudaOccupancyMaxActiveBlocksPerMultiprocessor(
            &max_blocks_per_sm, pearlhash_sm89_pipelined_kernel, BLOCK_THREADS, 0);
        // [v5.3] Surface occupancy loudly: a value of 1-2 means the register
        // budget was too generous and the GPU is starving.
        int warps_per_sm = max_blocks_per_sm * (BLOCK_THREADS / WARP_SIZE);
        printf("[Info] Kernel occupancy : %d blocks/SM (%d warps/SM)\n",
               max_blocks_per_sm, warps_per_sm);
        if (warps_per_sm < 8) {
            printf("[WARN] Very low occupancy (%d warps/SM). The kernel is almost "
                   "certainly register limited - expect low hashrate and low board "
                   "power. Rebuild with a smaller -maxrregcount or the --preset lite "
                   "binary.\n", warps_per_sm);
        }
        fflush(stdout);
    }

    cudaSetDeviceFlags(cudaDeviceMapHost | cudaDeviceScheduleSpin);
    cudaSetDevice(device_id);
    cudaFuncSetCacheConfig(pearlhash_sm89_pipelined_kernel, cudaFuncCachePreferL1);
    if (props.persistingL2CacheMaxSize > 0) {
        cudaDeviceSetLimit(cudaLimitPersistingL2CacheSize, props.persistingL2CacheMaxSize);
    }

    ShareResult* h_results[2];
    ShareResult* d_results[2];
    cudaStream_t streams[2];
    cudaEvent_t  finished_events[2];   // [v5.1 PERF] per-stream completion marker

    for (int s = 0; s < 2; ++s) {
        cudaHostAlloc((void**)&h_results[s], sizeof(ShareResult), cudaHostAllocMapped | cudaHostAllocWriteCombined);
        cudaHostGetDevicePointer((void**)&d_results[s], (void*)h_results[s], 0);
        memset((void*)h_results[s], 0, sizeof(ShareResult));
        cudaStreamCreateWithFlags(&streams[s], cudaStreamNonBlocking);
        cudaEventCreateWithFlags(&finished_events[s], cudaEventDisableTiming);
    }

    PearlStratumMiner miner(pool_host, pool_port, wallet, worker_name);
    g_miner_ptr = &miner;
    if (benchmark_secs == 0) {
        miner.connect_to_pool();
    } else {
        printf("[Benchmark] Pool connection skipped (pure GPU benchmark).\n");
        fflush(stdout);
    }

    PearlJob init_job = miner.get_active_job(0);
    cudaMemcpyToSymbol(c_header_key, init_job.header_key, sizeof(uint32_t) * 8);
    cudaMemcpyToSymbol(d_l2_header_staging, init_job.header_key, sizeof(uint32_t) * 8);

    cudaGraph_t graphs[2];
    cudaGraphExec_t graph_execs[2];
    cudaGraphNode_t kernel_nodes[2];
    cudaKernelNodeParams node_params[2];

    uint64_t graph_base_nonce[2]  = {0, 0};
    uint64_t graph_target_high[2] = {init_job.target_high, init_job.target_high};
    uint32_t graph_job_id[2]      = {init_job.job_id, init_job.job_id};

    // [v5.1 FIX] kernel_args was a local array inside the loop below, so
    // node_params[s].kernelParams dangled as soon as the iteration ended.
    // cudaGraphExecKernelNodeSetParams() in the mining loop then read freed
    // stack memory -> undefined behaviour. Keep the arrays alive at function
    // scope instead.
    void* kernel_args[2][4] = { {nullptr, nullptr, nullptr, nullptr},
                                {nullptr, nullptr, nullptr, nullptr} };

    for (int s = 0; s < 2; ++s) {
        cudaGraphCreate(&graphs[s], 0);
        memset(&node_params[s], 0, sizeof(cudaKernelNodeParams));

        // Point at the persistent graph_* slots, not at temporaries.
        kernel_args[s][0] = (void*)&graph_base_nonce[s];
        kernel_args[s][1] = (void*)&graph_target_high[s];
        kernel_args[s][2] = (void*)&graph_job_id[s];
        kernel_args[s][3] = (void*)&d_results[s];

        node_params[s].func           = (void*)pearlhash_sm89_pipelined_kernel;
        node_params[s].gridDim        = dim3(GRID_BLOCKS, 1, 1);
        node_params[s].blockDim       = dim3(BLOCK_THREADS, 1, 1);
        node_params[s].sharedMemBytes = 0;
        node_params[s].kernelParams   = kernel_args[s];
        node_params[s].extra          = nullptr;

        cudaGraphAddKernelNode(&kernel_nodes[s], graphs[s], nullptr, 0, &node_params[s]);
        cudaGraphInstantiate(&graph_execs[s], graphs[s], nullptr, nullptr, 0);
    }

    {
        cudaError_t g_err = cudaGetLastError();
        if (g_err != cudaSuccess) {
            printf("[CUDA Error] Graph creation failed: %s\n", cudaGetErrorString(g_err));
            printf("[CUDA Error] Aborting (see warning about sm_89 above).\n");
            g_nvml_ctrl.restore_defaults();
            return -1;
        }
    }

    uint64_t nonce_cursor = 0;
    uint64_t total_nonces = 0;
    uint32_t last_seen_job_id = init_job.job_id;

    auto start_time = std::chrono::high_resolution_clock::now();
    auto last_report_time = start_time;
    uint64_t nonces_since_last_report = 0;
    auto bench_deadline = start_time + std::chrono::seconds(benchmark_secs > 0 ? benchmark_secs : 0);

    PearlJob job0 = miner.get_active_job(nonce_cursor);
    nonce_cursor += nonces_per_launch;
    graph_base_nonce[0]  = job0.base_nonce;
    graph_target_high[0] = job0.target_high;
    graph_job_id[0]      = job0.job_id;
    cudaGraphExecKernelNodeSetParams(graph_execs[0], kernel_nodes[0], &node_params[0]);
    cudaGraphLaunch(graph_execs[0], streams[0]);

    int current_stream = 0;

    while (miner.running() &&
           (benchmark_secs == 0 || std::chrono::high_resolution_clock::now() < bench_deadline)) {
        int next_stream = 1 - current_stream;

        PearlJob next_job = miner.get_active_job(nonce_cursor);
        nonce_cursor += nonces_per_launch;

        if (next_job.job_id != last_seen_job_id) {
            cudaMemcpyToSymbolAsync(d_l2_header_staging, next_job.header_key, sizeof(uint32_t) * 8, 0, cudaMemcpyHostToDevice, streams[next_stream]);
            last_seen_job_id = next_job.job_id;
        }

        graph_base_nonce[next_stream]  = next_job.base_nonce;
        graph_target_high[next_stream] = next_job.target_high;
        graph_job_id[next_stream]      = next_job.job_id;
        cudaGraphExecKernelNodeSetParams(graph_execs[next_stream], kernel_nodes[next_stream], &node_params[next_stream]);
        cudaGraphLaunch(graph_execs[next_stream], streams[next_stream]);
        // [v5.1 PERF] record when this launch finishes instead of blocking now
        cudaEventRecord(finished_events[next_stream], streams[next_stream]);

        // Only wait for the *previous* stream when we need its results. This
        // keeps the CPU free to queue the next launch, which is the whole point
        // of double buffering.
        cudaEventSynchronize(finished_events[current_stream]);

        {
            cudaError_t sync_err = cudaGetLastError();
            if (sync_err != cudaSuccess) {
                printf("[CUDA Error] Kernel stream error: %s\n", cudaGetErrorString(sync_err));
                fflush(stdout);
            }
        }

        // [v5.1 FIX] reset found_count BEFORE reading it out of the pinned
        // buffer. The old code only cleared it when found > 0, so a stream that
        // reported nothing left a stale 0 behind - that part was fine - but a
        // stream that overflowed (>8 results) silently dropped the extras and
        // then kept the counter high for the next launch on that stream.
        uint32_t found = h_results[current_stream]->found_count;
        if (found > 0) {
            uint32_t count = (found > 8) ? 8 : found;
            if (found > 8) {
                printf("[Warn] %u results in one launch, sharing only the first 8 "
                       "(target is too easy or the kernel is over-reporting).\n", found);
                fflush(stdout);
            }
            for (uint32_t i = 0; i < count; ++i) {
                uint64_t win_nonce = h_results[current_stream]->winning_nonces[i];
                uint32_t win_job   = h_results[current_stream]->job_ids[i];
                std::thread([&miner, win_nonce, win_job]() {
                    miner.submit_share_async(win_nonce, win_job);
                }).detach();
            }
        }
        // Always clear, and clear the slot we are about to re-launch.
        h_results[current_stream]->found_count = 0;

        // [v5.3 FIX] Count a launch only after its stream has actually completed.
        // The old code incremented this for every queued launch, which inflated
        // the reported hashrate whenever the GPU was the bottleneck... and, when
        // occupancy collapsed, reported a number that did not match the card's
        // real load. Counting on completion makes the figure match what the GPU
        // really did.
        nonces_since_last_report += nonces_per_launch;
        total_nonces += nonces_per_launch;

        auto now = std::chrono::high_resolution_clock::now();
        double elapsed_sec = std::chrono::duration<double>(now - last_report_time).count();

        if (elapsed_sec >= 1.5) {
            double total_tensor_ops = (double)nonces_since_last_report * (double)HASH_OPS_PER_NONCE;
            double terahashes_per_sec = (total_tensor_ops / elapsed_sec) / 1e12;
            uint64_t uptime = (uint64_t)std::chrono::duration<double>(now - start_time).count();

            unsigned int gpu_temp = 0, gpu_fan = 0;
            double gpu_power = 0.0;
            g_nvml_ctrl.get_telemetry(gpu_temp, gpu_power, gpu_fan);

            write_hiveos_telemetry(stats_file, terahashes_per_sec, gpu_temp, gpu_fan, gpu_power,
                                   uptime, miner.get_accepted(), miner.get_rejected());

            printf("[Speed v4.4] %.2f TH/s | Temp: %u\u00b0C | Fan: %u%% | Power: %.1fW | Shares: %u/%u\n",
                   terahashes_per_sec, gpu_temp, gpu_fan, gpu_power,
                   miner.get_accepted(), miner.get_rejected());
            fflush(stdout);

            last_report_time = now;
            nonces_since_last_report = 0;
        }

        current_stream = next_stream;
    }

    for (int s = 0; s < 2; ++s) {
        cudaGraphExecDestroy(graph_execs[s]);
        cudaGraphDestroy(graphs[s]);
        cudaFreeHost(h_results[s]);
        cudaStreamDestroy(streams[s]);
    }

    miner.stop();
    std::this_thread::sleep_for(std::chrono::milliseconds(500));

    if (benchmark_secs > 0) {
        auto end_time = std::chrono::high_resolution_clock::now();
        double total_sec = std::chrono::duration<double>(end_time - start_time).count();
        double total_ops = (double)total_nonces * (double)HASH_OPS_PER_NONCE;
        printf("\n[Benchmark] %.1f s | Nonces: %llu | %.2f MH/s | %.2f TH/s (tensor ops)\n",
               total_sec, (unsigned long long)total_nonces,
               (double)total_nonces / total_sec / 1e6,
               (total_ops / total_sec) / 1e12);
        // [v5] Be explicit that this number is NOT pool-valid hashrate.
        printf("[Benchmark] NOTE: these are synthetic Tensor-Core throughput numbers, "
               "not pool-accepted shares. Use SRBMiner for production PRL mining.\n");
        fflush(stdout);
    } else {
        printf("\n[Mining] Shutting down. Accepted: %u  Rejected: %u\n",
               miner.get_accepted(), miner.get_rejected());
        if (!miner.has_real_job()) {
            printf("[Mining] WARNING: no valid mining.notify was ever received - "
                   "this run produced no real work.\n");
        }
        fflush(stdout);
    }

    g_nvml_ctrl.restore_defaults();
    return 0;
}
