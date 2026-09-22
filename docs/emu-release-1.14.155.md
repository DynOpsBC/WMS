# DKÇ / EMU 1.14.155

Yerleştirme ekranındaki yönlendirilmiş okutma akışına tek adımlı geri dönüş eklendi.

- Geri tuşu veya **Önceki Adım**, formu kapatmadan yalnızca bir önceki adıma döner.
- Daha önce doğrulanmış raf, ürün ve girilmiş miktar korunur.
- Operatör yalnızca hatalı adımı yeniden okutur.
- İlk adımda geri tuşu mevcut davranışla formu kapatır.
- Devam eden hedef raf doğrulaması sırasında geri dönülürse eski sunucu cevabı operatörü yeniden ileri taşımaz.

Bu sürüm yalnız Android terminal güncellemesidir. DKÇ Business Central paketi değişmemiştir; mevcut paket **1.14.2.16** olarak kalır.

Doğrulama: 381 birim testi geçti, release lint hatası yok, standart ve tarihsel imzalı iki APK'nın paket kimliği, sürümü ve sertifikası doğrulandı.

- Standart APK SHA-256: `500821817b9dd39e7e81c3255390f125c9bc8b521c2a80720dff7011fa93397a`
- Uyumlu APK SHA-256: `c3ba15f4f6745ba85957a0eb7f588d7eb0aa158c7d7b6f492137775fea91c9ca`
