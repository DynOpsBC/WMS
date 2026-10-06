import subprocess, os, re, json, shutil, hashlib
from pathlib import Path
apk=Path('android/app/build/outputs/apk/bade/release/app-bade-release.apk')
sdk=Path('/Users/kaanodabas/Library/Android/sdk/build-tools/35.0.0')
env=dict(os.environ, JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home')
cert=subprocess.check_output([str(sdk/'apksigner'),'verify','--print-certs',str(apk)],env=env,text=True)
m=re.search(r'certificate SHA-256 digest: ([a-f0-9]+)',cert)
assert m and m[1]=='ea7710af652faf6beff836d64327159b021c0561297cf9ae60987d26592b81eb', 'Unexpected signing certificate'
package=subprocess.check_output([str(sdk/'aapt'),'dump','badging',str(apk)],text=True).splitlines()[0]
assert "name='com.dynops.bcwms.bade'" in package and "versionCode='200132'" in package and "versionName='1.14.132-bade'" in package, package
print(package)
print('Release signing certificate verified.')
out=Path('releases/BADE-1.14.132')
name='BCWMS-BADE-1.14.132-RELEASE.apk'
shutil.copy2(apk,out/name)
sha=hashlib.sha256((out/name).read_bytes()).hexdigest()
manifest=dict(versionCode=200132,versionName='1.14.132-bade',apkUrl='https://github.com/DynOpsBC/WMS/releases/download/android-v1.14.132-bade/'+name,sha256=sha,releaseNotes='BADE: İlk seçimden sonra terminal değiştirmek için Yönetici PIN’i gerekir. Yanlış PIN veya iptal mevcut terminali değiştirmez. Production modül erişim kuralı korunur.')
(out/'latest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(out/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256((out/f).read_bytes()).hexdigest()+'  '+f+'\n' for f in (name,'latest.json')))
print('APK SHA256:',sha)
