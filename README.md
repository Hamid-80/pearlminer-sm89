# PearlMiner SM89

> ماینر سفارشی **pearlhash** برای RTX 4070 Ti روی HiveOS
> Custom pearlhash miner for RTX 4070 Ti (Ada / sm_89) on HiveOS

📖 **[راهنمای کامل فارسی →](GUIDE-FA.md)**

---

## ⚠️ هشدار مهم / Important warning

**این پروژه برای پژوهش و یادگیری است، نه ماینینگ تولیدی.**

**برای ماینینگ واقعی PRL از [SRBMiner-Multi](https://github.com/doktor83/SRBMiner-Multi/releases) استفاده کنید** — محصولی بالغ که سال‌ها بهینه و با استخرها تست شده است.

> This is a **research/benchmark** project, not a production miner.
> For real PRL mining use **SRBMiner-Multi**. The Stratum client was improved
> in v5 but has **not** been validated against a live pool.

| موضوع | وضعیت |
|---|---|
| کرنل Tensor Core INT8 | ✅ کارا |
| ساختار HiveOS | ✅ کامل |
| پروتکل Stratum | ⚠️ اصلاح‌شده اما تست‌نشده با استخر واقعی |
| ماینینگ تولیدی | ❌ **از SRBMiner استفاده کنید** |

---

## چه چیزی در v5 درست شد

v4.4 چند باگ جدی داشت که ماینر را عملاً بی‌فایده می‌کرد:

| # | باگ | تأثیر | رفع |
|---|---|---|---|
| ۱ | **VRAM روی 405-810 MHz قفل بود** | pearlhash حافظه‌بر است → هش‌ریت سقوط می‌کرد | قفل حذف شد، حافظه استوک |
| ۲ | `mining.notify` پارس نمی‌شد | هدر بلوک واقعی هرگز خوانده نمی‌شد | پارس کامل job_id/seed/target |
| ۳ | `mining.submit` آرایه ۳ عضوی | استخر همه shareها را رد می‌کرد | آرایه ۵ عضوی استاندارد |
| ۴ | `target_high` ثابت `0xFFFF0000` | سختی استخر نادیده گرفته می‌شد | از پاسخ استخر خوانده می‌شود |
| ۵ | هش روی داده ساختگی | share نامعتبر | فلگ `valid` — تا job نیاید submit نمی‌شود |
| ۶ | بنچمارک و ماین یکی | اعداد گمراه‌کننده | تفکیک + هشدار صادقانه |

---

## چه چیزی در v5.8 درست شد

v5.7 هنوز چند باگ جدی در کلاینت Stratum و حلقه‌ی GPU داشت که shareها را نامعتبر یا گم می‌کرد:

| # | باگ | تأثیر | رفع |
|---|---|---|---|
| ۱ | **اولین لانچ بدون `cudaEventRecord`** | تکرار اول حلقه `found_count` را می‌خواند در حالی که کرنل هنوز می‌نوشت → data race و خراب شدن بافر نتیجه برای لانچ بعدی | ثبت `finished_events[0]` بلافاصله پس از اولین لانچ |
| ۲ | **`submit_share_async` بدون قفل می‌خواند `current_job`** | یک ترد جدا از job_id_str نیمه‌نوشته می‌خواند و با job اشتباه submit می‌کرد | گرفتن کپی job_id_str/ntime زیر `job_mutex` و چک تطابق `win_job == current_job.job_id` (shareهای stale رد می‌شوند) |
| ۳ | **`send()` همزمان از چند ترد** | چند submit همزمان بایت‌ها را روی سوکت مخلوط می‌کردند → JSON خراب به استخر | `submit_mutex` + `send_all` (در برابر short write هم مقاوم) |
| ۴ | **بدون framing newline در `recv`** | یک پیام در چند `recv` یا چند خط در یک `recv` → jobها گم می‌شد (در `POOL-CONNECTION-FA.md` مستند شده بود) | بافر انباشتی + تفکیک روی `\n` → `handle_line` |
| ۵ | **`extranonce2`/`ntime` ثابت `"00000000"`** | استخر همه shareها را رد می‌کرد | پارس `extranonce1`/`extranonce2_size` از `mining.subscribe` (آرایه‌ای و object) و `ntime` از `mining.notify`؛ `extranonce2` یکتا و افزایشی |
| ۶ | **پارس موضعی نبود** | استاندارد Stratum `params` را به‌صورت آرایه می‌فرستد، نه کلید نام‌دار → job_id خالی می‌ماند | fallback موضعی (با آگاهی از عمق براکت) برای `job_id`/`prevhash`/`ntime` |
| ۷ | **`cudaHostAllocWriteCombined` روی بافر خوانده‌شده** | خواندن CPU هر تکرار از حافظه‌ی uncached کند/ناپایدار | فقط `cudaHostAllocMapped` |
| ۸ | **race روی `d_l2_header_staging` هنگام تغییر job** | دو استریم یک نماد device مشترک می‌خواندند/نوشتند | همگام‌سازی کرنل قبلی قبل از بازنویسی staging |
| ۹ | **پاسخ authorize بررسی نمی‌شد** | worker رد شده ولی ماینر بی‌صدا ادامه می‌داد | تشخیص `result:false` + چاپ دلیل + هشدار هنگام خروج |
| ۱۰ | **تطبیق `\"id\":4` شکننده** | `id:40` هم match می‌شد؛ شمارش share اشتباه | dispatch هر خط کامل و parse عددی `id` |

همچنین: پاک‌سازی stream/buffer در مسیر خطای گراف، اعتبارسنجی port در `parse_pool_url`، و همگام‌سازی رشته‌ی نسخه (v4.3/v4.4 → v5.8) در کل سورس، workflow و فلایت‌شیت.

> ⚠️ کلاینت Stratum در v5.8 کامل‌تر شد ولی **هنوز با استخر زنده PRL تست نشده است** (CUDA در محیط توسعه نبود). منطق پارسر با ۴۵ تست واحد روی داده‌های واقعی‌نمای Kryptex (object-form و array-form) تأیید شده. برای ماینینگ تولیدی از SRBMiner استفاده کنید.

---

## نصب سریع

```bash
cd /hive/miners/custom/
wget https://github.com/Hamid-80/pearlminer-sm89/releases/download/v5.8/pearlminer_sm89-5.8.tar.gz
tar -xzf pearlminer_sm89-5.8.tar.gz
chmod +x pearlminer_sm89/*
cd pearlminer_sm89
./pearlminer_sm89 --benchmark 30
```

راهنمای کامل نصب: **[GUIDE-FA.md](GUIDE-FA.md)**

---

## فلایت‌شیت‌ها

| فایل | ماینر | وضعیت |
|---|---|---|
| [`hiveos-flight-sheet-kryptex-srb.json`](hiveos-flight-sheet-kryptex-srb.json) | SRBMiner 3.8.3 | ✅ **توصیه‌شده** |
| [`hiveos-flight-sheet-custom-pearlminer_sm89.json`](hiveos-flight-sheet-custom-pearlminer_sm89.json) | این ریپو | ⚠️ آزمایشی |

وارد کردن در HiveOS: **Flight Sheet → Import JSON**

---

## تنظیمات اورکلاک پیشنهادی برای ۴۰۷۰ Ti

| پارامتر | حالت پایدار | حداکثر هش‌ریت |
|---|---|---|
| Core Offset | +200 MHz | +300 MHz |
| Lock Core | 2500 MHz | 2650 MHz |
| Lock Memory | **5001 MHz** | **5001 MHz** |
| Power Limit | 160 W | 180 W |
| نتیجه | ~153 TH/s @ 144W | ~161 TH/s @ 170W |

> 💡 `Lock Memory` را پایین نگذارید — pearlhash حافظه‌بر است.

---

## CLI

```bash
./pearlminer_sm89 --pool HOST:PORT --wallet WALLET --worker NAME
./pearlminer_sm89 --benchmark 30
./pearlminer_sm89 --cclock 2730
./pearlminer_sm89 --help
```

---

## ساخت از سورس

```bash
# preset اصلی — حداکثر register reuse
nvcc -O3 -arch=sm_89 --use_fast_math -Xptxas=-dlcm=ca \
  -DN_FRAGMENTS=16 -DBLOCKS_PER_SM=5 \
  pearl_miner_sm89_ultimate.cu -o pearlminer_sm89 \
  -Xcompiler=-static-libstdc++,-static-libgcc -lpthread -ldl

# preset سبک — occupancy بیشتر
nvcc -O3 -arch=sm_89 --use_fast_math -Xptxas=-dlcm=ca \
  -DN_FRAGMENTS=8 -DBLOCKS_PER_SM=8 \
  pearl_miner_sm89_ultimate.cu -o pearlminer_sm89_lite \
  -Xcompiler=-static-libstdc++,-static-libgcc -lpthread -ldl
```

---

## نیازمندی‌ها

- RTX 40 Series (Ada Lovelace, **sm_89**) — روی ۳۰ سری یا AMD کار نمی‌کند
- CUDA 12.4+
- درایور NVIDIA 550+
- HiveOS یا Linux

---

## مجوز

MIT

## مشارکت

Pull Request خوش‌آمد است — مخصوصاً:
- تست `mining.notify` با استخر واقعی PRL
- پورت کرنل به `sm_86` (RTX 30 series)
