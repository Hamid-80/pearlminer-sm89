# تشخیص — از v5.9 (ساختگی) تا v6.0 (واقعی)

> تاریخ: ۲۰۲۶-۱۱-۱۲ · بررسی: v5.8 → v5.9 → **v6.0**
> نتیجهٔ v5.9: ماینر نمی‌توانست share معتبر Pearl تولید کند (عدم تطابق معماری با cuPOW واقعی).
> **بررسی نهایی v6.0: مشکل با جایگزینی بک‌اند با CPPminer واقعی (MIT) حل شد — shareهای واقعی پذیرفته می‌شوند.**

---

## ۰) وضعیت v6.0 — راه‌حل واقعی (بروزرسانی)

v5.9 و قدیمی‌تر یک کرنل **ساختگی** (`pearl_miner_sm89_ultimate.cu`) داشتند که استخر هر share آن
را رد می‌کرد (بخش ۳). از v6.0، این ریپو به یک بسته‌بندی HiveOS از ماینر **واقعی و متن‌باز
[CPPminer](https://github.com/1640675651/CPPminer)** (MIT، tag v1.0) برای sm_89 تبدیل شده است.
CPPminer الگوریتم واقعی Pearl را پیاده می‌کند و در برابر **LuckyPool / Herominers / Kryptex**
اثبات شده است. کرنل ساختگی حذف شد.

| مرحلهٔ واقعی Pearl | v5.9 (ساختگی) | v6.0 (CPPminer واقعی) |
|---|---|---|
| ماتریس A/B از commitment | نویز Philox مستقل ❌ | CUTLASS NoisyGEMM از commitment ✅ |
| blake3 commitment | هیچ ❌ | blake3 واقعی ✅ |
| GEMM در ابعاد تولید | MMAهای ریز ❌ | CUTLASS fused GEMM ✅ |
| XOR-reduce + jackpot | XOR-fold ظاهری ≈ | fused XOR + jackpot ✅ |
| `blake3(jackpot) < target (nbits)` | pseudo-blake3 ❌ | blake3 واقعی + nbits ✅ |
| Merkle proof | هیچوقت ❌ | ساخت Merkle proof ✅ |
| share = proof بزرگ | nonce ۵عضوی ❌ | `plain_proof` = base64(bincode proof) + gzip ✅ |

**تأیید:** فقط shareهای accepted در داشبورد استخر (مثلاً `pool.kryptex.com/prl`) سند واقعی‌اند.
بک‌اند CUDA ابتدا برای Pascal بهینه شده؛ روی Ada (sm_89) از طریق DP4A اجرا می‌شود و share
معتبر تولید می‌کند، ولی هنوز برای hashrate اوجِ Ada بهینه نیست.

میان‌بر: فلایت‌شیت `hiveos-flight-sheet-custom-pearlminer_sm89.json` (v6.0) یا بیلد روی rig با
`bash build-sm89.sh --install`.

---

## ۱) نشانه (v5.9)

- کارت گرافیک زیر بار است (کرنل در حال اجراست).
- نمایشگر ریگ عددی مثل ~۱۴۹ (TH/s) نشان می‌دهد.
- استخر (Kryptex `prl.kryptex.network:7048`) **هیچ hashrate/Share قبول‌شده‌ای ثبت نمی‌کند**.

این نشانه دقیقاً یعنی: GPU کار می‌کند ولی **shareهای ارسالی نامعتبرند** و استخر همه را رد می‌کند.

---

## ۲) الگوریتم واقعی Pearl چیست؟ (طبق منابع رسمی)

Pearl (PRL) یک L1 با **Proof-of-Useful-Work (PoUW)** است. الگوریتم ماینینگ آن **pearlhash** نامیده می‌شود و در واقع **cuPOW / NoisyGEMM** است (منابع: arXiv:2606.04819v2 «An Empirical Study of Pearl's cuPOW Protocol»، مخزن رسمی `github.com/pearl-research-labs/pearl`، BitcoinTalk topic 5584502).

هر تلاش ماینینگ واقعی این مراحل را دارد:

1. ساخت دو ماتریس **A (M×K)** و **B (N×K)** با درایه‌ها در **{−۶۴…۶۴}** (int8). ابعاد تولید: **M = N = ۱۳۰۷۲**.
2. **commit به ماتریس‌ها با blake3**.
3. افزودن **structured noise مشتق‌شده از commitment** (این پیوند nonce/job به عملوندهاست).
4. محاسبهٔ **NoisyGEMM روی کاشی‌های rank-R**.
5. **XOR-reduce کاشی‌ها** و انباشت **jackpot**.
6. بررسی `blake3(jackpot) < target` که در `nbits` کد شده (mainnet `nbits=0x1b014f8a`، سختی ~۱۰.۵M).
7. در صورت موفقیت، **ساخت Merkle proof**.

### share واقعی Pearl چیست؟

> «یک share در pearlhash یک عدد کوچک مثل سکه‌های مبتنی بر هش نیست؛ یک proof کامل از کار واقعی GPU است (صدها KB).» — اپراتور استخر در BitcoinTalk

استخر هر share را با ۴ بررسی اعتبارسنجی می‌کند: بازهٔ درایه‌ها [−۶۴,۶۴]، سازگاری Merkle proof، تطابق کاشی GEMM بازمحاسبه‌شده با jackpot، و هش jackpot با target. به همین دلیل SRBMiner-MULTI از **فشرده‌سازی gzip** برای ترافیک استخر استفاده می‌کند (تا ۸۰٪ کاهش).

---

## ۳) این پروژه چه می‌کند؟ (و چرا با واقعی نمی‌خواند)

کرنل `pearl_miner_sm89_ultimate.cu` یک **تقریب ساختگی** است:

| مرحلهٔ واقعی Pearl | این پروژه | تطابق |
|---|---|---|
| ماتریس‌های A/B از commitment | نویز Philox4x32-10 مستقل از commitment | ❌ |
| blake3 commitment | هیچ commitmentی | ❌ |
| NoisyGEMM M=N=131072 | MMAهای ریز m16n8k32 روی ۱۶ fragment | ❌ (مقیاس و ساختار اشتباه) |
| XOR-reduce کاشی‌ها + jackpot | XOR-fold جمع‌کننده‌ها به transcript | ≈ فقط ظاهری |
| `blake3(jackpot) < target (nbits)` | ۲ راند pseudo-blake3 + مقایسهٔ ۶۴بیتی truncation | ❌ |
| Merkle proof | هیچوقت ساخته نمی‌شود | ❌ |
| share = proof بزرگ (صدها KB) | `mining.submit` ۵عضوی با یک nonce | ❌ |

### سه عدم تطابق کشنده

1. **قالب share اشتباه** — یک nonce در `mining.submit` می‌فرستد، در حالی که Pearl یک proof بزرگ می‌خواهد. استخر هر submit را به‌عنوان malformed رد می‌کند.
2. **الگوریتم اشتباه** — Philox+INT8-MMA+pseudo-blake3، نه NoisyGEMM واقعی با commitment/Merkle proof. استخر کاشی GEMM را بازمحاسبه می‌کند و تطابقی نمی‌یابد.
3. **هش نهایی اشتباه** — ۲ راند pseudo-blake3 + مقایسهٔ ۶۴بیتی، نه blake3 واقعی روی jackpot با nbits.

---

## ۴) آیا با ویرایش فایل قابل ترمیم است؟

**خیر.** برای قبول‌انداختن share باید کل پروتکل cuPOW پیاده‌سازی شود:

- NoisyGEMM در ابعاد تولید (M=N=131072) با commitment و structured noise.
- blake3 واقعی (نه ۲ راند).
- ساخت Merkle proof.
- **قالب سریال‌سازی proof که استخر می‌پذیرد** — این **مستندنشده** است (فقط در ماینرهای بسته‌متن مثل alpha-miner و خود استخر). مقالهٔ arXiv هم آن را مشخص نمی‌کند.
- فشرده‌سازی gzip برای ترافیک.

این‌ها فراتر از یک فایل CUDA است و عملاً بازنویسی کامل + مهندسی معکوس قالب proof بسته است. ابزارهای واقعی از قبل وجود دارند (بخش ۵).

---

## ۵) راه‌حل واقعی — از این ماینرها استفاده کنید

| ماینر | وضعیت | دستور |
|---|---|---|
| **SRBMiner-MULTI** | ✅ توصیه‌شده، پایدار | `--algorithm pearlhash --pool prl.kryptex.network:7048 --wallet WALLET.WORKER` |
| **Neil Pearl Miner** | ✅ متن‌باز (NVIDIA/AMD) | BitcoinTalk topic 5586806 |
| **vllm-miner رسمی Pearl** | ✅ متن‌باز | `github.com/pearl-research-labs/pearl` (دایرکتوری `miner/`) |
| ForgeMiner / PeakMiner / ARCMiner | ✅ | طبق راهنمای Kryptex |

شما از قبل فلایت‌شیت SRBMiner-MULTI را دارید: `hiveos-flight-sheet-kryptex-srb.json`. برای ماینینگ واقعی PRL به آن سوییچ کنید.

---

## ۶) تغییرات v5.9 در این پروژه (صادقانه)

v5.9 الگوریتم را «درست» نمی‌کند (غیرممکن است، بخش ۴). بلکه:

- **بنر هشدار صادقانه** در استارتاپ: توضیح می‌دهد که کرنل ساختگی است و استخر هر share را رد می‌کند.
- **برچسب سرعت صادقانه**: «SYNTHETIC (NOT pool-valid)» به‌جای ادعای TH/s.
- **تشخیص runtime**: بعد از ۶۰ ثانیه با ۰ share قبول‌شده، دلیل را چاپ می‌کند.
- **nonce ۳۲بیتی (۸ hex)**: اصلاح قالب stratum (هرچند برای Pearl کشنده است، نه فقط nonce).
- **همگام‌سازی نسخه** به v5.9 در کل سورس.

این پروژه فقط برای **پژوهش/بنچمارک** باقی می‌ماند، نه ماینینگ تولیدی.

---

## ۷) منابع

- arXiv:2606.04819v2 — «An Empirical Study of Pearl's cuPOW Protocol»
- مخزن رسمی: https://github.com/pearl-research-labs/pearl
- Kryptex Pool Pearl: https://pool.kryptex.com/prl
- miningpoolstats.stream/pearl
- BitcoinTalk ANN: topic 5584502 (Pearl/PoUW)، topic 5586806 (Neil Pearl Miner)
