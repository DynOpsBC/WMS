# BADE test ortamı

13.11.2026 kullanıcı talimatıyla BADE geliştirmeleri ve WMS test yayınları **Sand1311** ortamında sürdürülür.

- Tenant: `3bbd610b-95e4-47b3-8b48-4f7caf717bc3`
- Ortam: `Sand1311` (Sandbox)
- WMS şirketi: `BS İlaç Kozmetik San.Tic.A.Ş.`
- Şirket kimliği: `752a7ff6-9946-f011-be59-002248d35589`
- İlk kontrolde BCWMSApp `1.14.1.189` zaten kurulu bulundu; yeniden yayımlanmadı.

AL bağlantısında `Bade - Sand1311 (fast publish)` kullanılır. Şema güncellemelerinde normal seçim `Synchronize` olur.

BADE Android ilk girişte Sand1311'i öncelikli yoklar; Sand2809 ve E-DefterSandbox ortamlarına elle geçiş de korunur. Kurulu uygulamanın daha önce kaydettiği ortam seçimi değişmez: mevcut cihazda çıkış/giriş yapıp **Sand1311 → BS İlaç Kozmetik San.Tic.A.Ş.** seçilmelidir.

Element4 / Kitoko bağlantıları ayrı müşteriye aittir; bu BADE ortam değişikliği onları değiştirmez. İş bazında sunucu testi ile fiziksel terminal / yazıcı UAT sonucu ayrı kaydedilir.
