BADE Android **1.14.170** (200170)

BADE terminal sürümü 1.14.169'dan 1.14.170'e yükseltildi ve mevcut geliştirmeler yeni terminal güncellemesi olarak paketlendi.

- Mal kabulde **Palet LP → Lot Grubu Ekle** üzerinden birden fazla lot grubu hazırlanabilir. Bu özellik için BCWMSApp **1.14.1.125** gerekir; [önceki yayındaki BC paketi](https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.169-bade) kullanılabilir.
- Aynı iç lota farklı tedarikçi lotları girilmesi ve ilk sayımı koruyarak aynı sayfada ikinci sayım yapılması bu pakette bulunmuyor. Bunlar ek geliştirme gerektiriyor.
- Bu yayın terminal APK güncellemesidir; BC ortamına uzantı kurulumu yapmaz.

Kaynak: `28b9fa66de975ad5b3cdd58c7a0d6dce4f1db910`. Yeniden derleme: `:app:assembleBadeRelease -PreleaseVersionCode=200170 -PreleaseVersionName=1.14.170`.

Doğrulama: 473 Android birim testi geçti. Release derlemesi ve release lint kontrolü başarılı. APK paket kimliği `com.dynops.bcwms.bade`, sürüm kodu `200170`; imza sertifikası 1.14.169 ile aynı. APK SHA-256: `127a1b1f0885d3fc3f9ca692d9ba01c61f0ab653aab22ca7ee7f345b92f21aa8`.
