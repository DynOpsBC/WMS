"""Build a private Kitoko delivery from the tested, secret-free agent ZIP."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--agent-zip', type=Path, required=True)
parser.add_argument('--agent-secrets', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
secret = json.loads(args.agent_secrets.read_text(encoding='utf-8-sig'))
assert secret['schemaVersion'] == 1
assert secret['stationId'] == 'KITOKO.KITOKO.MAIN.PRINT01'
assert secret['routing']['tenantId'] == secret['routing']['companyId'] == 'KITOKO'
assert 'businessCentral' not in secret and 'agent' in secret
with zipfile.ZipFile(args.agent_zip) as archive:
    assert archive.testzip() is None
    assert not any(name.endswith('.secrets.json') for name in archive.namelist())
digest = hashlib.sha256(args.agent_zip.read_bytes()).hexdigest()
out = args.output.resolve()
out.mkdir(mode=0o700, parents=True, exist_ok=False)
source = Path(__file__).parent
installer = (source / 'kurulum.ps1').read_text(encoding='utf-8-sig')
assert installer.count('__AGENT_SHA256__') == 1
(out / 'kurulum.ps1').write_text(installer.replace('__AGENT_SHA256__', digest), encoding='utf-8-sig')
shutil.copyfile(source / 'KURULUM.bat', out / 'KURULUM.bat')
shutil.copyfile(args.agent_zip, out / 'bcwms-print-agent-1.0.0-win-x64.zip')
shutil.copyfile(args.agent_secrets, out / 'print-agent.runtime.secrets.json')
(out / 'print-agent.runtime.secrets.json').chmod(0o600)
(out / 'ONCE-BENI-OKU.txt').write_text('''KİTOKO — Windows yazıcı ajanı

Hedef BC ortamı: DemoSandbox
Şirket: KITOKO-TR-DEMO-V1
İstasyon: KITOKO.KITOKO.MAIN.PRINT01

Yarın Windows 10/11 64-bit bilgisayarda:
1. ZIP'e sağ tıklayıp Tümünü ayıkla. ZIP'in içinden çalıştırma.
2. KURULUM.bat dosyasına çift tıkla. Yönetici veya .NET kurulumu gerekmez.
3. Açılan ajan panelinde Yazıcılar sekmesine geç. Etiket ve/veya belge
   yazıcısını seçip Ayarları Kaydet ve Bağlan düğmesine bas.
   Yazıcı listede yoksa önce üreticinin Windows sürücüsünü kur, sonra Yenile.
   Etiket dilini yazıcının desteklediği ZPL / ESCPOS / RAW olarak seç.
4. El terminalindeki Yazıcılar ekranında listeyi yenile ve yazıcıyı seç.
   İlk fiziksel etiket/belge denemesini bilgisayarın başında yap.

Bağlantı bilgileri hazırdır; elle JSON seçmek veya anahtar yazmak gerekmez.
Ayarlar o Windows kullanıcısına bağlı DPAPI şifrelemesiyle kaydedilir.
Ajan Windows oturum açılışında otomatik başlar. Masaüstündeki
KITOKO Yazıcı Ajanı kısayolundan paneli açabilirsin.
Yazıcı bağlı değilken de uygulama kurulur; yazıcıyı daha sonra seçebilirsin.
Yeniden kurulumda aynı istasyonun yazıcı seçimleri korunur. Çalışan ajan
varsa önce saat yanındaki simgeden Çıkış seç.

Bu özel paket KİTOKO bağlantı bilgileri içerir. Sadece kurulacak bilgisayara
aktar; GitHub/ortak kanala yükleme. İstasyonu aynı anda tek bilgisayarda
çalıştır. Bu bağlantı yalnız yukarıdaki BC ortamı/şirketine ayrılmıştır.
Kurulumdan sonra klasördeki açık ayar dosyası silinir; orijinal ZIP ayrı
olarak özel tutulmalıdır. İlk Windows ve fiziksel yazıcı testi sahada yapılır.
''', encoding='utf-8-sig')
files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()}
(out / 'paket-dogrulama.json').write_text(json.dumps({
    'customer': 'KITOKO', 'environment': 'DemoSandbox',
    'company': 'KITOKO-TR-DEMO-V1', 'station': secret['stationId'],
    'runtime': 'win-x64', 'selfContained': True, 'files': files,
    'windowsPhysicalPrinterTestCompleted': False,
}, ensure_ascii=False, indent=2), encoding='utf-8')
zip_path = out.with_suffix('.zip')
if zip_path.exists():
    raise FileExistsError(zip_path)
with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_STORED) as archive:
    for p in sorted(out.iterdir()):
        archive.write(p, arcname=out.name + '/' + p.name)
zip_path.chmod(0o600)
print(json.dumps({'folder': str(out), 'zip': str(zip_path),
                  'sha256': hashlib.sha256(zip_path.read_bytes()).hexdigest()}))
