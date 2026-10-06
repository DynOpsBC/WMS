BADE Android **1.14.132-bade** (versionCode **200132**).

- İlk terminal seçimi serbesttir. Cihazda terminal seçildikten sonra başka terminale geçmek için Yönetici PIN’i gerekir.
- “Terminal değiştir” ekranında yeni terminal ve yönetici seçilir. PIN, BC üzerinden yeni terminal için doğrulanır; yalnızca doğrulanmış Yönetici yanıtıyla değişiklik kaydedilir.
- Yanlış PIN, bağlantı hatası veya iptal mevcut terminali değiştirmez. Kayıtlı terminal boşaltılarak onay atlanamaz.
- Onay veren yönetici operatör olarak otomatik giriş yapmaz; yeni terminalin kullanıcı giriş ekranı açılır.
- Kural BADE’ye özeldir ve tüm ortamlarda geçerlidir. 1.14.131 sürümündeki BADE Production modül erişim kuralı korunur.

Doğrulama: 378 BADE + 369 EMU birim testi, emülatörde 9 giriş/terminal ekranı testi ve BADE lint başarılı. Testler sahte BC bağlantısıyla çalıştı; canlı verilerde işlem yapılmadı.

Yalnızca BADE APK’sı ve BADE güncelleme kanalı güncellenir. EMU yayını ve BC uzantısı değişmez.
