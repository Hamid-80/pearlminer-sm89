# راهنمای کامل فارسی — PearlMiner SM89 v5

> ماینر سفارشی pearlhash برای RTX 4070 Ti روی HiveOS
> **مهم: قبل از استفاده، بخش «هشدار مهم» را بخوانید.**

---

## ⚠️ هشدار مهم — اول این را بخوانید

این پروژه یک **بنچمارک/پژوهش** برای الگوریتم pearlhash است، نه یک ماینر آماده‌ی تولید.

**وضعیت واقعی:**

| موضوع | وضعیت |
|---|---|
| کرنل Tensor Core INT8 | ✅ درست و کارا |
| ساختار HiveOS (h-manifest و…) | ✅ کامل |
| **پارس پروتکل استخر (Stratum)** | ⚠️ ناقص — در v5 بهبود یافت اما تست‌نشده |
| **ارسال share معتبر به استخر** | ❌ **تضمینی نیست** |
| استفاده برای درآمد واقعی | ❌ **از SRBMiner استفاده کنید** |

**توصیه‌ی اکید:** برای ماینینگ واقعی PRL از **SRBMiner-Multi** استفاده کنید. این پروژه برای یادگیری و آزمایش است.

---

## 📋 فهرست

1. [نیازمندی‌ها](#نیازمندیها)
2. [نصب سریع روی HiveOS](#نصب-سریع-روی-hiveos)
3. [ساخت فلایت‌شیت](#ساخت-فلایتشیت)
4. [بنچمارک بدون استخر](#بنچمارک-بدون-استخر)
5. [تنظیمات اورکلاک پیشنهادی](#تنظیمات-اورکلاک-پیشنهادی)
6. [تغییرات نسخه v5](#تغییرات-نسخه-v5)
7. [عیب‌یابی](#عیبیابی)
8. [پرسش‌های متداول](#پرسشهای-متداول)

---

## نیازمندی‌ها

| مورد | حداقل | توضیح |
|---|---|---|
| کارت گرافیک | **RTX 40 Series (Ada)** | فقط `sm_89` کامپایل شده. روی ۳۰ سری یا AMD کار **نمی‌کند** |
| سیستم عامل | HiveOS (Linux) | نسخه ویندوز هم پشتیبانی می‌شود |
| درایور NVIDIA | 550 یا بالاتر | برای NVML |
| CUDA | 12.4 | برای کامپایل |

> ⚠️ **RTX 4070 Ti / 4070 / 4060 Ti** کار می‌کند. روی **RTX 3080/3090** کار نمی‌کند.

---

## نصب سریع روی HiveOS

### روش ۱ — دانلود بسته آماده (ساده‌ترین)

```bash
# ۱. وارد ریگ شوید
ssh user@192.168.0.100

# ۲. دانلود آخرین نسخه
cd /hive/miners/custom/
wget https://github.com/Hamid-80/pearlminer-sm89/releases/download/v5.0/pearlminer_sm89-5.0.tar.gz

# ۳. استخراج
tar -xzf pearlminer_sm89-5.0.tar.gz

# ۴. قابل اجرا کردن
chmod +x pearlminer_sm89/pearlminer_sm89
chmod +x pearlminer_sm89/pearlminer_sm89_lite
chmod +x pearlminer_sm89/h-config.sh
chmod +x pearlminer_sm89/h-run.sh

# ۵. تست
cd pearlminer_sm89
./pearlminer_sm89 --benchmark 30
```

### روش ۲ — کامپایل از سورس

روی ریگ HiveOS:

```bash
# نصب CUDA (اگر نیست)
apt install -y cuda-toolkit-12-4

# دانلود سورس
cd ~
wget https://raw.githubusercontent.com/Hamid-80/pearlminer-sm89/main/pearl_miner_sm89_ultimate.cu

# کامپایل — preset اصلی
nvcc -O3 -arch=sm_89 --use_fast_math -Xptxas=-dlcm=ca \
  -DN_FRAGMENTS=16 -DBLOCKS_PER_SM=5 \
  pearl_miner_sm89_ultimate.cu -o pearlminer_sm89 \
  -Xcompiler=-static-libstdc++,-static-libgcc -lpthread -ldl

# کامپایل — preset سبک (occupancy بیشتر)
nvcc -O3 -arch=sm_89 --use_fast_math -Xptxas=-dlcm=ca \
  -DN_FRAGMENTS=8 -DBLOCKS_PER_SM=8 \
  pearl_miner_sm89_ultimate.cu -o pearlminer_sm89_lite \
  -Xcompiler=-static-libstdc++,-static-libgcc -lpthread -ldl
```

---

## ساخت فلایت‌شیت

### از رابط وب HiveOS

۱. برو به **Flight Sheets** → **+**
۲. تنظیمات زیر را وارد کن:

| فیلد | مقدار |
|---|---|
| Coin | `PRL` |
| Wallet | آدرس کیف پول PRL شما |
| Pool | `prl.kryptex.network:7048` |
| Miner | `Custom` |
| Name | `pearlminer_sm89` |
| Install URL | `https://github.com/Hamid-80/pearlminer-sm89/releases/download/v5.0/pearlminer_sm89-5.0.tar.gz` |
| Template | `%WAL%.%WORKER_NAME%` |

۳. در **Setup Miner Config** وارد شو و در فیلد **User config** بنویس:

```
--pool %CUSTOM_URL% --wallet %CUSTOM_TEMPLATE% --cclock 2730
```

۴. ذخیره کن و فلایت‌شیت را روی worker اعمال کن.

### با وارد کردن JSON

فایل `hiveos-flight-sheet-pearlminer.json` را از ریپو بگیر و در HiveOS از طریق
**Flight Sheet → سه‌نقطه → Import JSON** وارد کن.

---

## بنچمارک بدون استخر

این حالت هیچ اتصالی به استخر ندارد و فقط توان محاسباتی GPU را می‌سنجد:

```bash
cd /hive/miners/custom/pearlminer_sm89

# preset اصلی
./pearlminer_sm89 --benchmark 60

# preset سبک
./pearlminer_sm89_lite --benchmark 60
```

خروجی نمونه:

```
[Benchmark] 60.0 s | Nonces: 12345678 | 205.76 MH/s | 168.45 TH/s (tensor ops)
[Benchmark] NOTE: these are synthetic Tensor-Core throughput numbers,
            not pool-accepted shares.
```

> ⚠️ عدد `TH/s` خروجی **هش‌ریت استخر نیست**. فقط سرعت اجرای عملیات ماتریسی است.

### کدام preset بهتر است؟

هر دو را ۶۰ ثانیه اجرا کن و عدد بالاتر را انتخاب کن:

| preset | Fragments | Blocks/SM | مناسب برای |
|---|---|---|---|
| `pearlminer_sm89` | 16 | 5 | حداکثر استفاده از Register |
| `pearlminer_sm89_lite` | 8 | 8 | Occupancy بیشتر، Register spill کمتر |

---

## تنظیمات اورکلاک پیشنهادی

بر اساس بنچمارک‌های واقعی RTX 4070 Ti روی pearlhash:

### حالت پایدار (توصیه‌شده)

```
Core Clock Offset : +200  MHz
Lock Core Clock   : 2500  MHz
Lock Memory Clock : 5001  MHz
Power Limit       : 160   W
```

**نتیجه انتظاری:** ~۱۵۳ TH/s با ~۱۴۴ وات

### حالت حداکثر هش‌ریت

```
Core Clock Offset : +300  MHz
Lock Core Clock   : 2650  MHz
Lock Memory Clock : 5001  MHz
Power Limit       : 180   W
```

**نتیجه انتظاری:** ~۱۶۱ TH/s با ~۱۷۰ وات

### حالت کم‌مصرف

```
Lock Core Clock   : 2400  MHz
Power Limit       : 150   W
```

**نتیجه انتظاری:** ~۱۴۵ TH/s با ~۱۳۴ وات

> 💡 **نکته مهم:** `Lock Memory Clock` را روی pearlhash **هرگز پایین نگذارید** — این الگوریتم حافظه‌بر است و حافظه‌ی کم‌فرکانس هش‌ریت را نابود می‌کند. این باگ در v4.4 وجود داشت و در v5 رفع شد.

---

## تغییرات نسخه v5

### 🐛 باگ‌های رفع‌شده

| # | مشکل در v4.4 | رفع در v5 |
|---|---|---|
| ۱ | **قفل حافظه روی 405-810 MHz** — هش‌ریت را نابود می‌کرد | حذف شد، حافظه روی فرکانس استوک |
| ۲ | **پروتکل Stratum ناقص** — `mining.notify` پارس نمی‌شد | پارس کامل job_id، seed، target |
| ۳ | **فرمت `mining.submit` نادرست** — آرایه ۳ عضوی | آرایه ۵ عضوی استاندارد |
| ۴ | **`target_high` ثابت** `0xFFFF0000` | از استخر خوانده می‌شود |
| ۵ | **هش ساختگی** بدون job واقعی | فلگ `valid` — تا job نرسد submit نمی‌شود |
| ۶ | **بنچمارک و ماین یکسان** | خروجی صادقانه و تفکیک‌شده |

### ✨ بهبودها

- پارس JSON مقاوم‌تر برای پاسخ‌های استخر
- گزارش وضعیت در زمان خروج (accepted/rejected)
- هشدار صریح اگر هیچ job واقعی دریافت نشد
- کامنت‌گذاری شفاف درباره‌ی ماهیت بنچمارک

---

## عیب‌یابی

### ماینر اجرا نمی‌شود

```bash
# بررسی معماری کارت
nvidia-smi --query-gpu=name,compute_cap --format=csv

# باید 8.9 باشد. اگر 8.6 (RTX 30) یا 8.0 (A100) است، کار نمی‌کند.
```

### خطای `CUDA initialization failed`

```bash
# بررسی درایور
nvidia-smi

# بررسی CUDA
nvcc --version
```

### هش‌ریت صفر است

چند دلیل ممکن:
1. **بدون استخر** — بنچمارک را اجرا کنید: `./pearlminer_sm89 --benchmark 30`
2. **job دریافت نشده** — لاگ را ببینید: باید `[Stratum] New job #...` بیاید
3. **کارت sm_89 نیست** — خروجی `nvidia-smi` را بررسی کنید

### HiveOS هش‌ریت نشان نمی‌دهد

فایل `/tmp/pearlminer_stats.json` را بررسی کنید:

```bash
cat /tmp/pearlminer_stats.json
```

باید JSON معتبر با `khs` باشد.

---

## پرسش‌های متداول

### ❓ آیا این ماینر از SRBMiner سریع‌تر است؟

**نه.** صادقانه: SRBMiner یک محصول بالغ است که سال‌ها بهینه شده. این پروژه
برای پژوهش و یادگیری است. برای ماینینگ واقعی **از SRBMiner استفاده کنید**.

### ❓ چطور هش‌ریت واقعی PRL را بالا ببرم؟

۱. **SRBMiner** را با تنظیمات بالا اجرا کنید
۲. **اورکلاک** را دقیق تنظیم کنید (بخش اورکلاک بالا)
۳. **استخر با کارمزد کمتر** انتخاب کنید
۴. **خنک‌سازی** خوب باشد (دما زیر ۶۵ درجه)

### ❓ می‌شود روی RTX 3080 اجرا کرد؟

با کامپایل مجدد برای `sm_86`:
```bash
nvcc -O3 -arch=sm_86 --use_fast_math ... 
```
اما تست نشده و ممکن است خطا بدهد.

### ❓ چرا فایل `.cu` انقدر بزرگ است؟

شامل کلاینت Stratum، مدیریت NVML، لاگ HiveOS و کرنل در یک فایل واحد است —
برای سادگی کامپایل با یک دستور `nvcc`.

---

## مجوز

MIT — استفاده آزاد با ذکر منبع.

## مشارکت

Pull Request خوش‌آمد است. مخصوصاً:
- تست `mining.notify` با استخرهای واقعی PRL
- بهینه‌سازی کرنل برای sm_86 (RTX 30 series)
