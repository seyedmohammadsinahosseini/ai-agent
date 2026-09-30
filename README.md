# AI Terminal — نسخه‌ی PoC (Proof of Concept)

این پوشه یک نسخه‌ی اولیه‌ی کاری از «ترمینال هوش مصنوعی» است که سه لایه‌ی توافق‌شده
را به‌هم وصل می‌کند:

```
Flutter (client/)  <-- HTTP/WebSocket -->  FastAPI (server/)  <-- pybind11 -->  C++ Engine (engine/)
```

جزئیات کامل معماری در [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) توضیح داده شده.

## چه چیزی الان کار می‌کند؟

- **موتور C++ (`engine/`)**: کلاس `RiskClassifier` هر دستور را قطعی (بدون وابستگی به
  مدل AI) به یکی از چهار سطح `SAFE` / `CONFIRM` / `DANGEROUS` / `BLOCKED` طبقه‌بندی
  می‌کند. کلاس `PtySession` دستور را در یک pseudo-terminal اجرا می‌کند (این نسخه با
  POSIX PTY برای تست در سندباکس لینوکسی؛ نسخه‌ی نهایی ویندوزی باید با ConPTY نوشته شود
  — محل دقیقش در `pty_session.hpp` مشخص شده).
- **سرور FastAPI (`server/`)**: یک API محلی روی پورت 8765 که:
  - با کلید API کاربر (BYOK: OpenAI / Anthropic / Gemini) به مدل هوش مصنوعی وصل می‌شود.
  - دستور پیشنهادی مدل را از موتور C++ رد می‌کند تا سطح ریسک مشخص شود.
  - دستورات `SAFE` را خودکار اجرا می‌کند؛ برای `CONFIRM`/`DANGEROUS` منتظر تایید
    صریح کاربر می‌ماند؛ دستورات `BLOCKED` را هرگز اجرا نمی‌کند.
  - هر درخواست نیازمند یک Bearer Token محلی (تولیدشده هنگام اولین اجرا) است.
- **کلاینت Flutter (`client/`)**: یک رابط چت با نمایش:
  - رنگ‌بندی سطح ریسک هر دستور پیشنهادی،
  - دکمه‌ی «تایید و اجرا» برای دستورات نیازمند تایید،
  - دیالوگ هشدار قوی (تایپ عبارت تایید) برای دستورات خطرناک،
  - صفحه‌ی تنظیمات برای وارد کردن کلید API هر سرویس.

## اجرای محلی (برای توسعه/تست)

```bash
# 1) کامپایل موتور C++
cd engine && mkdir -p build && cd build
cmake -Dpybind11_DIR=$(python3 -c "import pybind11; print(pybind11.get_cmake_dir())") ..
cmake --build . -j4

# 2) نصب وابستگی‌های پایتون و اجرای سرور
cd ../../server
pip install -r requirements.txt
python3 -m app.main
# سرور روی http://127.0.0.1:8765 بالا می‌آید

# 3) بیلد و اجرای کلاینت (Web، برای تست سریع بدون ویندوز)
cd ../client
flutter pub get
flutter build web
# فایل‌های build/web به‌صورت خودکار توسط همان سرور FastAPI سرو می‌شوند
```

سپس مرورگر را روی `http://127.0.0.1:8765` باز کنید.

> نکته: برای اجرای واقعی روی ویندوز (Desktop نهایی)، باید:
> 1. `pty_session.hpp` با پیاده‌سازی واقعی ConPTY جایگزین شود.
> 2. `client` با `flutter build windows` کامپایل و به‌صورت اپ native نصب شود (نه Web).
> 3. ذخیره‌ی کلید API از طریق پکیج `keyring` روی ویندوز به‌صورت خودکار از
>    Windows Credential Manager استفاده می‌کند.

## چیزهایی که در این PoC عمداً ساده‌سازی شده و در نسخه‌ی نهایی باید تکمیل شود

- Sandboxing واقعی اجرای دستورات (Windows Job Objects / Microsoft Execution Containers).
- Redaction خودکار اطلاعات حساس (رمز، توکن) قبل از ارسال خروجی ترمینال به AI ابری.
- Audit log کامل و پایدار (این نسخه فقط لاگ ساده‌ی uvicorn دارد).
- Snapshot/Undo (System Restore Point، یا حذف به Recycle Bin به‌جای حذف قطعی).
- امضای دیجیتال (Code Signing) باینری‌های نهایی و بسته‌بندی با MSIX/Installer.
- تست امنیتی جدی‌تر روی `risk_classifier.hpp` (فازتست، پوشش الگوهای بیشتر PowerShell/cmd).
