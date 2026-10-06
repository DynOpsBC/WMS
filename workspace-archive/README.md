# EL_TERMINAL kaynak yedekleri — 6 Ekim 2026

Bu dal, yerelde kalmış kaynak ve dokümanları kurtarma amacıyla saklar; yayın veya test onayı değildir.

Çalışma kopyaları `backup/local-20261006/<klasör>` dallarında; stash kayıtları `stash-0`, `stash-1`, `stash-2` dallarında korunur. Tam eşleme ve commitler BACKUP-MANIFEST.json dosyasındadır. Stash geri yüklemesinde manifestteki `stash_commit` kullanılabilir.

Kaynak dosyaları `workspace-archive/` altında özgün klasör yollarıyla saklanır. Mevcut çalışma dosyaları ve staged değişiklikler korunmuştur. Derleme önbellekleri, imza anahtarları, parolalar ve üretilmiş paket kopyaları bu kaynak yedeğine dahil değildir. Hiçbir yerel dosya silinmedi. Son BADE APK/BC paketi GitHub android-v1.14.168-bade yayınındadır.
