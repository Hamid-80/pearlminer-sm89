# راهنمای فارسی PearlMiner SM89 (v6.0 — واقعی)

این راهنما به شما می‌گوید چگونه با ریپو فعلی **واقعاً** Pearl (PRL) ماین کنید.

---

## ۱) این پروژه چیست؟

از v6.0، این ریپو یک بسته‌بندی HiveOS از ماینر **واقعی و متن‌باز CPPminer** (MIT) برای
کارت‌های **RTX 40 سری (Ada Lovelace / sm_89)** است. یعنی:

- کرنل ساختگی قدیمی حذف شد.
- بک‌اند واقعی Pearl یعنی **cuPOW / NoisyGEMM** (CUTLASS fused GEMM+XOR+jackpot + blake3 Merkle
  proof) از CPPminer بیلد و در tarball قرار می‌گیرد.
- shareها به قالب واقعی Pearl یعنی `plain_proof` = base64(bincode proof) + gzip ارسال می‌شوند.
- استخرهای LuckyPool / Herominers / Kryptex این shareها را **می‌پذیرند**.

---

## ۲) پیش‌نیازها

- کارت گرافیک RTX 40 سری (sm_89). برای RTX 30 (Ampere) از `SM_ARCH=86` استفاده کنید.
- HiveOS با درایور NVIDIA 550+.
- یک آدرس کیف‌پول Pearl (PRL) معتبر (با کیف‌پول رسمی Pearl یا یک صرافی که PRL پشتیبانی می‌کند).

---

## ۳) نصب با فلایت‌شیت (ساده‌ترین راه)

1. فایل `hiveos-flight-sheet-custom-pearlminer_sm89.json` را از این ریپو بردارید.
2. در HiveOS: **Flight Sheets → Import JSON** → این فایل را وارد کنید.
3. آدرس کیف‌پول PRL خود را در فیلد **Wallet** فلایت‌شیت بگذارید.
4. فلایت‌شیت را به کارت اعمال کنید.

HiveOS به‌طور خودکار `pearlminer_sm89-6.0.tar.gz` را از release v6.0 دانلود و در
`/hive/miners/custom/pearlminer_sm89/` نصب می‌کند. آدرس استخر پیش‌فرض:
`prl-ae.kryptex.network:7048` (استخر Kryptex).

---

## ۴) نصب دستی

```bash
cd /hive/miners/custom/
wget https://github.com/Hamid-80/pearlminer-sm89/releases/download/v6.0/pearlminer_sm89-6.0.tar.gz
tar -xzf pearlminer_sm89-6.0.tar.gz
chmod +x pearlminer_sm89/*
cd pearlminer_sm89
./pearlminer_sm89 --algo pearl --backend cuda --devices 0 \
  --pool stratum+tcp://prl-ae.kryptex.network:7048 \
  --wallet prl1<کیف_پول_شما> --worker rig01 \
  --pool-pass d=2097152 --api-port 4028
```

---

## ۵) چگونه مطمئن شوم واقعاً ماین می‌کند؟

دو راه برای تأیید:

**الف) API محلی (همان منبع h-stats.sh):**
```bash
curl -s http://127.0.0.1:4028/summary | jq '{hs: .hashrate.total[0], accepted: .shares.accepted, rejected: .shares.rejected}'
```
اگر `accepted > 0` باشد، shareهای واقعی پذیرفته شده‌اند.

**ب) داشبورد استخر:**
به `https://pool.kryptex.com/prl` بروید (با کیف‌پول خودتان) و hashrate غیرصفر و تعداد
shareهای accepted را ببینید. **این تنها سند قطعی ماینینگ واقعی است.**

اگر بعد از ۲–۳ دقیقه هیچ shareی پذیرفته نشد:
- آدرس کیف‌پول را چک کنید (`prl1...`).
- استخر را چک کنید (با `curl` به `prl-ae.kryptex.network:7048`).
- لاگ را ببینید: `tail -f /var/log/miner/custom/pearlminer_sm89/*.log`.
- با `--mock` تست آفلاین بگیرید: `./pearlminer_sm89 --backend cuda --devices 0 --mock` (بدون استخر، تا اولین share + تأیید zk-pow).

---

## ۶) چند کارتی (Multi-GPU)

بک‌اند Pearl CUDA فعلاً یک GPU در هر پروسس را پشتیبانی می‌کند. برای چند کارتی، در HiveOS برای
هر کارت یک فلایت‌شیت جدا بسازید یا در **Extra config** کارت دوم `--devices 1` بنویسید
(و کارت سوم `--devices 2`، و غیره).

---

## ۷) تنظیمات اورکلاک پیشنهادی برای ۴۰۷۰ Ti

pearlhash به شدت وابسته به **INT8/DP4A و GEMM** (حافظه‌بر) است؛ برخلاف SHA256 که core-bound است.

| پارامتر | حالت پایدار |
|---|---|
| Core Lock | 2500–2700 MHz |
| Memory Lock | استوک یا ۵۰۱ MHz بالا |
| Power Limit | ۱۶۰–۲۰۰ W |
| Fan | برای دما زیر ۷۰°C |

این مقادیر را با داشبورد استخر (نه عدد محلی) بهینه کنید: هدف، **بیشترین shareهای accepted
در دقیقه** است، نه بیشترین عدد hashrate محلی.

---

## ۸) ساخت از سورس روی rig

اگر می‌خواهید خودتان بیلد کنید (یا نسخهٔ دیگری از CPPminer را):
```bash
bash build-sm89.sh --install     # CPPminer v1.0 را برای sm_89 بیلد و نصب می‌کند
SM_ARCH=86 bash build-sm89.sh --install   # برای RTX 30
```
نیازها: CUDA Toolkit 12.x، Rust، cmake، g++، git.

---

## ۹) استخر جایگزین (LuckyPool)

CPPminer به‌طور پیش‌فرض به LuckyPool Pearl وصل می‌شود. برای استفاده از LuckyPool به‌جای Kryptex،
در فلایت‌شیت فیلد **url** را خالی بگذارید و در **Extra config** چیزی ننویسید؛ یا مستقیم:
```bash
./pearlminer_sm89 --algo pearl --backend cuda --devices 0 \
  --wallet prl1<کیف_پول> --worker rig01 --api-port 4028
```

---

## ۱۰) اگر نسخه‌های قدیمی روی rig بود

```bash
sudo rm -rf /hive/miners/custom/pearlminer_sm89
# سپس نصب v6.0 را انجام دهید (مرحلهٔ ۳ یا ۴)
```
نسخه‌های ≤ v5.9 ساختگی بودند و share تولید نمی‌کردند؛ حتماً پاک شوند.

---

## مجوز

MIT. باینری ماینر = CPPminer (MIT). بسته‌بندی این ریپو = MIT. جزئیات در `LICENSE` و `NOTICE`.
