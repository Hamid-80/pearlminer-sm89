# PearlMiner SM89 v5 — آموزش نصب در گیت‌هاب

این فایل توضیح می‌دهد چطور فایل‌های این بسته را در گیت‌هاب خودتان آپلود کنید.

---

## 📦 محتوای بسته

| فایل | توضیح |
|---|---|
| `pearl_miner_sm89_ultimate.cu` | سورس کامل ماینر (نسخه v5 بهبودیافته) |
| `GUIDE-FA.md` | راهنمای کامل فارسی |
| `hiveos-flight-sheet-kryptex-srb.json` | فلایت‌شیت SRBMiner + Kryptex |
| `hiveos-flight-sheet-custom-pearlminer_sm89.json` | فلایت‌شیت ماینر سفارشی |
| `INSTALL-GITHUB.md` | همین فایل |

---

## روش ۱ — آپلود از رابط وب گیت‌هاب (ساده‌ترین)

### قدم ۱: رفتن به ریپو

مرورگر را باز کنید و بروید به:

```
https://github.com/Hamid-80/pearlminer-sm89
```

### قدم ۲: آپلود فایل‌ها

۱. روی دکمه **Add file** (سبز) کلیک کنید
۲. گزینه **Upload files** را انتخاب کنید
۳. فایل‌ها را از این پوشه بکشید و رها کنید:
   - `pearl_miner_sm89_ultimate.cu`
   - `GUIDE-FA.md`
   - `hiveos-flight-sheet-kryptex-srb.json`
   - `hiveos-flight-sheet-custom-pearlminer_sm89.json`

> ⚠️ فایل `hiveos-flight-sheet-custom-pearlminer_sm89.json` ممکن است جایگزین
> فایل قبلی هم‌نام شود — این درست است.

۴. پایین صفحه، در فیلد **Commit changes** بنویسید:

```
v5: fix VRAM lock, stratum protocol, submit format + Persian guide
```

۵. دکمه سبز **Commit changes** را بزنید

---

## روش ۲ — با Git در خط فرمان

اگر Git نصب دارید:

```bash
# کلون ریپو
git clone https://github.com/Hamid-80/pearlminer-sm89.git
cd pearlminer-sm89

# کپی فایل‌های جدید
cp /path/to/pearl_miner_sm89_ultimate.cu .
cp /path/to/GUIDE-FA.md .
cp /path/to/hiveos-flight-sheet-kryptex-srb.json .
cp /path/to/hiveos-flight-sheet-custom-pearlminer_sm89.json .

# کامیت و پوش
git add .
git commit -m "v5: fix VRAM lock, stratum protocol, submit format + Persian guide"
git push origin main
```

---

## بعد از آپلود — ساخت Release

برای اینکه Install URL کار کند، باید یک Release بسازید:

### قدم ۱: ساخت تگ

۱. در صفحه ریپو → **Releases** (ستون راست)
۲. **Draft a new release**
۳. **Choose a tag** → بنویسید: `v5.0`
۴. **Create new tag: v5.0 on publish**

### قدم ۲: عنوان و توضیحات

**Release title:**
```
PearlMiner SM89 v5.0
```

**Describe this release:**
```markdown
## v5.0 — باگ‌فیکس مهم

### رفع باگ‌ها
- **قفل VRAM حذف شد** — v4.4 حافظه را روی 810 MHz قفل می‌کرد که برای
  الگوریتم حافظه‌بر pearlhash فاجعه بود
- **پروتکل Stratum اصلاح شد** — `mining.notify` حالا درست پارس می‌شود
- **فرمت `mining.submit` درست شد** — از آرایه ۳ عضوی به ۵ عضوی استاندارد
- **target از استخر خوانده می‌شود** — نه مقدار ثابت
- **فلگ valid** — تا job واقعی نیاید share ارسال نمی‌شود
- **تفکیک بنچمارک از ماین** با هشدار صادقانه

### فایل‌های جدید
- `GUIDE-FA.md` — راهنمای کامل فارسی
- `hiveos-flight-sheet-kryptex-srb.json` — فلایت‌شیت آماده
```

### قدم ۳: ساخت بسته نصب

اگر می‌خواهید Install URL کار کند، باید بسته `.tar.gz` بسازید.
**راه ساده:** از GitHub Actions خودتان استفاده کنید — پس از push،
workflow به‌طور خودکار بسته را می‌سازد.

---

## ✅ بعد از آپلود

### ۱. بررسی کامپایل

برو به تب **Actions** در ریپو. باید workflow `Build HiveOS Custom Miner Package`
به‌طور خودکار اجرا شود. اگر سبز شد = کامپایل موفق.

### ۲. استفاده در HiveOS

روی ریگ خود:

```bash
ssh user@192.168.0.100
cd /hive/miners/custom/
wget https://github.com/Hamid-80/pearlminer-sm89/releases/download/v5.0/pearlminer_sm89-5.0.tar.gz
tar -xzf pearlminer_sm89-5.0.tar.gz
chmod +x pearlminer_sm89/*
cd pearlminer_sm89
./pearlminer_sm89 --benchmark 30
```

### ۳. افزودن فلایت‌شیت

در HiveOS:
۱. **Flight Sheets** → **+**
۲. **Import JSON** را بزنید
۳. محتوای `hiveos-flight-sheet-kryptex-srb.json` را paste کنید

---

## ⚠️ یادآوری مهم

این ماینر برای **پژوهش و یادگیری** است.

**برای ماینینگ واقعی PRL از SRBMiner استفاده کنید.** دلیل: پروتکل Stratum
اصلاح شد اما با استخر واقعی تست نشده است (CUDA روی سیستم توسعه‌دهنده نبود).

جزئیات کامل در `GUIDE-FA.md`.
