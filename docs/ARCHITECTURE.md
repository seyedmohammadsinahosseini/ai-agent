# معماری AI Terminal (PoC)

## لایه‌ها

```
Flutter UI  <--HTTP/WebSocket-->  FastAPI (Python)  <--pybind11-->  C++ Engine
   client/                           server/                          engine/
```

- **engine/** : ماژول C++ که با pybind11 به پایتون export می‌شه.
  - `pty_session`: اجرای دستور در یک pseudo-terminal (روی ویندوز نهایی: ConPTY، روی این
    محیط توسعه/لینوکس: POSIX forkpty برای تست).
  - `risk_classifier`: تابع C++ خالص و deterministic که هر دستور را به یکی از سه سطح
    ریسک `SAFE` / `CONFIRM` / `DANGEROUS` طبقه‌بندی می‌کند. این لایه کاملاً مستقل از
    خروجی مدل هوش مصنوعی است (دفاع لایه‌به‌لایه در برابر اشتباه/injection مدل).

- **server/** : سرویس FastAPI که روی `127.0.0.1` بالا می‌آید.
  - `/chat` : پیام کاربر را می‌گیرد، به مدل AI (OpenAI/Claude/Gemini - BYOK) می‌فرستد و
    دستور پیشنهادی را برمی‌گرداند.
  - `/execute` : دستور را از طریق موتور C++ ریسک‌سنجی و در صورت لزوم اجرا می‌کند.
  - `/ws/terminal` : کانال WebSocket برای استریم زنده‌ی خروجی ترمینال.
  - احراز هویت با یک توکن محلی تصادفی (فقط localhost).

- **client/** : اپ Flutter (در نسخه نهایی Windows Desktop، در این PoC هدف Web برای
  پیش‌نمایش در سندباکس).

## جریان یک درخواست (مثال)
1. کاربر در چت می‌نویسد: «فایل‌های قدیمی توی Downloads رو پاک کن»
2. FastAPI این متن را با تاریخچه به مدل AI می‌فرستد؛ مدل دستور پیشنهادی
   (مثلاً `Remove-Item -Recurse ...`) را برمی‌گرداند، همراه با توضیح فارسی ساده.
3. FastAPI دستور را به `risk_classifier` (C++) می‌دهد.
4. اگر `SAFE` → بلافاصله اجرا و خروجی استریم می‌شود.
   اگر `CONFIRM` یا `DANGEROUS` → به کاربر در UI نمایش داده می‌شود و منتظر تایید می‌ماند.
5. خروجی دستور (ConPTY/PTY) به صورت زنده روی WebSocket به Flutter پخش می‌شود.

## نکات امنیتی پیاده‌سازی‌شده در PoC
- Risk classification در C++ (نه صرفاً در پرامپت مدل).
- توکن API به‌صورت جداگانه ذخیره می‌شود، نه هاردکد در کد.
- عدم استفاده از `shell=True` / string concatenation برای اجرای دستور.
- API فقط روی loopback (127.0.0.1) گوش می‌دهد و هر درخواست نیازمند Bearer token محلی است.
