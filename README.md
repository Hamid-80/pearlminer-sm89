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

## نصب سریع

```bash
cd /hive/miners/custom/
wget https://github.com/Hamid-80/pearlminer-sm89/releases/download/v5.0/pearlminer_sm89-5.0.tar.gz
tar -xzf pearlminer_sm89-5.0.tar.gz
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
