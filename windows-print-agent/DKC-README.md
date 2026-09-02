# DKC Production Print Agent

Bu paket DKC üretim dashboard'undan gelen ZPL son ürün etiketlerini Windows
yazıcı kuyruğuna iletir. Mevcut BCWMS Print Agent'tan tamamen ayrı kurulur;
ayar, log, tekrar-engelleme günlüğü, başlangıç kaydı ve çalışma kilidi paylaşmaz.

## İlk kurulum

1. `DKC-Production-Print-Agent-Setup.exe` dosyasını yazıcının kurulu olduğu
   normal Windows kullanıcısıyla çalıştırın.
2. Açılan **DKC Production Print Agent** ekranında **Azure Ayarları** sekmesine
   geçin ve yalnız DKC için üretilen `print-agent.runtime.secrets.json`
   dosyasını içe aktarın.
3. **Yazıcılar** sekmesinde etiket yazıcısını seçin, formatı `ZPL` yapın ve
   **Ayarları Kaydet ve Bağlan** düğmesine basın.
4. **Etiket Testi** ile yerel çıktıyı, ardından **Buluta Eşitle** ve Azure smoke
   işiyle uçtan uca bağlantıyı doğrulayın.

Secret dosyasını WMS agent'a aktarmayın. İçe aktarma ve başarılı kayıt sonrası
düz metin dosyayı kurumun güvenli silme politikasına göre kaldırın. Ayarlar
Windows DPAPI CurrentUser ile `%LOCALAPPDATA%\DynOps\DKC Production Print Agent`
altında korunur ve başka Windows kullanıcısına kopyalanamaz.

Uygulama kullanıcı girişinde otomatik başlar. Pencereyi kapatmak uygulamayı
sistem tepsisine küçültür; tamamen durdurmak için tepsi menüsünden **Çıkış**
seçeneğini kullanın.
