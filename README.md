# PearlMiner SM89 — REAL Pearl (PRL) miner for RTX 40 series

> بک‌اند واقعی **CPPminer** (MIT) برای Pearl (PRL) بسته‌بندی‌شده برای HiveOS روی **sm_89 / Ada Lovelace (RTX 40)**.
> A real, pool-valid Pearl (PRL) miner for **sm_89 / Ada Lovelace** on HiveOS, built from the MIT-licensed **CPPminer**.

📖 **[راهنمای کامل فارسی →](GUIDE-FA.md)** · **[DIAGNOSIS →](DIAGNOSIS.md)**

---

## این نسخه (v6.0) واقعی است / This release (v6.0) is REAL

از v6.0 به بعد، این ریپو یک ماینر **واقعی** Pearl است: بک‌اند کرنل با **CPPminer** جایگزین شد —
ماینر متن‌باز MIT که الگوریتم واقعی Pearl یعنی **cuPOW / NoisyGEMM** را پیاده می‌کند و در برابر
استخرهای **LuckyPool / Herominers / Kryptex** اثبات شده است. نسخه‌های ≤ v5.9 یک کرنل **ساختگی**
داشتند که استخر هر share آن را رد می‌کرد؛ منسوخ شده‌اند.

From v6.0 on, this repo is a **real** Pearl miner: the kernel backend is replaced by **CPPminer** —
an MIT-licensed, open-source miner that implements the real Pearl **cuPOW / NoisyGEMM** algorithm and
is proven against **LuckyPool / Herominers / Kryptex**. Versions ≤ v5.9 used a *synthetic* kernel
that pools always rejected; they are deprecated.

| مورد / Item | وضعیت / Status |
|---|---|
| بک‌اند / Backend | ✅ **CPPminer v1.0 (MIT)** — اثبات‌شده روی استخرهای واقعی |
| الگوریتم / Algorithm | ✅ واقعی **Pearl cuPOW**: CUTLASS fused GEMM + XOR + jackpot |
| proof و share | ✅ `plain_proof` = base64(**bincode** Merkle proof) + **gzip** (استخرهای `type:"v2"`) |
| هش نهایی / Final hash | ✅ **blake3** روی jackpot، مقایسه با target از `nbits` |
| اعتبارسنجی share توسط استخر / Pool-valid shares | ✅ بله (برخلاف v5.9) |
| معماری / Arch | sm_89 (Ada / RTX 40) از طریق DP4A؛ sm_86 (RTX 30) با `SM_ARCH=86` |

---

## Pearl واقعی چیست؟ / What real Pearl mining is

Pearl (PRL) یک L1 با **Proof-of-Useful-Work** است (hard fork بیت‌کوین، آوریل ۲۰۲۶): کار مفیدِ ماینر
**ضرب ماتریس** است، نه حدس هش تصادفی. الگوریتم ماینینگ (که CPPminer آن را پیاده کرده):

1. **NoisyGEMM** — ضرب ماتریس int8 (CUTLASS) روی GPU با نویز ساختاریافته‌ی مشتق‌شده از commitment.
2. ساخت **commitment** و درخت **Merkle** روی کاشی‌های GEMM.
3. محاسبهٔ **jackpot** از خروجی، و هش نهایی با **blake3**.
4. مقایسهٔ `blake3(jackpot)` با **target** (کدشده در `nbits`؛ سختی mainnet ~۱۰.۵M).
5. submit یک **proof بزرگ (ده‌ها KB)** به استخر — **نه** یک nonce ساده.

استخر هر share را با بازمحاسبهٔ کاشی GEMM، بررسی Merkle proof، و تطابق `blake3(jackpot) < target`
اعتبارسنجی می‌کند. به همین دلیل CPPminer برای استخرهای `type:"v2"` (Kryptex) proof را با **gzip**
فشرده می‌کند (~۳۵×).

Pearl (PRL) is an L1 Proof-of-Useful-Work chain (Apr 2026): the useful work is **matrix
multiplication**, not random hashing. CPPminer implements it: int8 NoisyGEMM via CUTLASS, structured
noise from a commitment, a Merkle tree over the GEMM tiles, a jackpot, a final **blake3** hash, and a
target encoded in `nbits`. The submitted share is a **large proof (tens of KB)**, gzip-wrapped for v2
pools — not a nonce. Sources: arXiv 2504.09971, arXiv 2606.04819, `pearl-research-labs/pearl`.

---

## استخرها / Pools

| استخر / Pool | آدرس stratum | منطقه / Region |
|---|---|---|
| **Kryptex** (پیش‌فرض فلایت‌شیت) | `stratum+tcp://prl.kryptex.network:7048` | جهانی |
| Kryptex AE (فلایت‌شیت فعلی) | `stratum+tcp://prl-ae.kryptex.network:7048` | خاورمیانه |
| Kryptex EU/US/SG/HK/RU/BR | `stratum+tcp://prl-<region>.kryptex.network:7048` | منطقه‌ای |
| LuckyPool | CPPminer به‌طور پیش‌فرض LuckyPool Pearl را استفاده می‌کند (حذف `--pool`) | جهانی |
| f2pool | `stratum+tcp://pearl.f2pool.com:5500` | جهانی |

داشبورد استخر: Kryptex `https://pool.kryptex.com/prl` — فقط shareهای **accepted** و hashrate غیرصفر سند واقعی ماینینگ‌اند.

---

## نصب سریع / Quick install (HiveOS)

1. در HiveOS: **Flight Sheets → Import JSON** → فایل [`hiveos-flight-sheet-custom-pearlminer_sm89.json`](hiveos-flight-sheet-custom-pearlminer_sm89.json).
2. آدرس کیف‌پول PRL خود را در فیلد **Wallet** وارد کنید.
3. فلایت‌شیت را به کارت اعمال کنید؛ HiveOS به‌صورت خودکار tarball را از release v6.0 نصب می‌کند.

نصب دستی / Manual:
```bash
cd /hive/miners/custom/
wget https://github.com/Hamid-80/pearlminer-sm89/releases/download/v6.0/pearlminer_sm89-6.0.tar.gz
tar -xzf pearlminer_sm89-6.0.tar.gz
chmod +x pearlminer_sm89/*
```

---

## تأیید اینکه واقعاً ماین می‌کند / Verify it really mines

پس از ~۶۰ ثانیه:
```bash
# آمار زنده از API خود CPPminer (همان منبعی که h-stats.sh می‌خواند)
curl -s http://127.0.0.1:4028/summary | jq '{hs: .hashrate.total[0], accepted: .shares.accepted, rejected: .shares.rejected}'
```
سپس در **داشبورد استخر** (مثلاً `pool.kryptex.com/prl`) «shareهای accepted» و hashrate غیرصفر را ببینید.
این تنها سند واقعی ماینینگ است؛ عدد HiveOS `khs` از همان endpoint `/hiveos` می‌آید.

> توجه: بک‌اند CUDA ابتدا برای Pascal بهینه شده؛ روی Ada (sm_89) از طریق DP4A اجرا می‌شود و
> **shareهای معتبر** تولید می‌کند، ولی هنوز برای hashrate اوجِ Ada بهینه نیست.

---

## ساخت از سورس روی rig / Build on the rig

```bash
# نیازها: CUDA Toolkit 12.x (nvcc)، Rust (cargo)، cmake، g++، git، curl
bash build-sm89.sh --install     # CPPminer v1.0 را برای sm_89 بیلد و در HiveOS نصب می‌کند
# برای RTX 30 (Ampere):   SM_ARCH=86 bash build-sm89.sh --install
```

---

## CLI واقعی / Real CLI (CPPminer)

```bash
./pearlminer_sm89 --algo pearl --backend cuda --devices 0 \
  --pool stratum+tcp://prl.kryptex.network:7048 \
  --wallet prl1<YOUR_WALLET> --worker rig01 \
  --pool-pass d=2097152 --api-port 4028
```
پرچم‌های مفید: `--devices N` (کارت؛ برای چند کارتی یک پروسس به ازای GPU)، `--batch-size N`،
`--verify` (تأیید zk-pow قبل از submit)، `--mock` (آفلاین تا اولین share + تأیید، بدون استخر).

---

## نیازمندی‌ها / Requirements

- RTX 40 series (Ada, **sm_89**)؛ RTX 30 (Ampere, sm_86) با `SM_ARCH=86`؛ کارت‌های AMD با بک‌اند OpenCL در upstream CPPminer.
- درایور NVIDIA 550+ (تأمین `libcuda.so`)؛ `libcudart.so` درون tarball بسته‌بندی شده.
- HiveOS یا هر Linux x86_64.

---

## مجوز / License

MIT. باینری ماینر = CPPminer (MIT، © نویسندگان آن)؛ بسته‌بندی این ریپو نیز MIT.
جزئیات: [`LICENSE`](LICENSE) و [`NOTICE`](NOTICE).

## مشارکت / Contributing

Pull request خوش‌آمد است — به‌ویژه: بهینه‌سازی CUTLASS برای Ada، تست با استخرهای واقعی و
گزارش hashrate واقعی روی 4070 Ti / 4090.
