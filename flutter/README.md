# Flutter POS

Bu papka `KIYIM DOKON` uchun Flutter POS dasturi.

## Hozir tayyor bo'lgan qism

- Login sahifasi
- Session saqlash (`shared_preferences`)
- Backend API bilan auth ulanishi
- Dashboard overview sahifasi
- Riverpod + GoRouter asosiy arxitekturasi

## Lokal ishga tushirish

1. Windows'da `Developer Mode` yoqing
2. PowerShell'da shu papkaga kiring
3. `.\run_windows.ps1` ni ishga tushiring

Yoki qo'lda:

```powershell
$env:PATH='D:\sovga\UY-DOKON\.flutter-sdk\bin;'+$env:PATH
flutter run -d windows
```

## Muhim

Flutter SDK lokal ravishda repo ichidagi `D:\sovga\UY-DOKON\.flutter-sdk` ichiga o'rnatiladi.
API default manzili: `https://unvercalapp.richman.uz/api`
