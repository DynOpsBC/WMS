#!/bin/zsh
# BADE MTE / LP kartı REF hatası için salt-okunur BC kontrolü.
# Kullanım: ./tools/bade-mte-check.sh [Environment]   (varsayılan Production)
# Gerekli: az login (BADE kiracısında yetkili hesap), python3.
set -e
T=3bbd610b-95e4-47b3-8b48-4f7caf717bc3
ENV=${1:-Production}
TOK=$(az account get-access-token --resource https://api.businesscentral.dynamics.com --tenant $T --query accessToken -o tsv)
H="Authorization: Bearer $TOK"
BASE="https://api.businesscentral.dynamics.com/v2.0/$T/$ENV"
CID=$(curl -fsS -H "$H" "$BASE/api/v2.0/companies" | python3 -c "import sys,json; v=json.load(sys.stdin)['value']; print(v[0]['id'])")
echo "Ortam: $ENV  Şirket: $CID"
echo; echo "== Yüklü uzantılar (WMS / Bade)"
curl -fsS -H "$H" "$BASE/api/microsoft/automation/v2.0/companies($CID)/extensions?\$filter=isInstalled%20eq%20true" \
 | python3 -c "import sys,json
for e in json.load(sys.stdin)['value']:
    n=e.get('displayName','')
    if any(k in n for k in ('WMS','Bade','BADE','Production')):
        print(f\"  {n}: {e.get('versionMajor')}.{e.get('versionMinor')}.{e.get('versionBuild')}.{e.get('versionRevision')}\")"
echo; echo "== Terminal kullanıcısının yetki setleri (BadeProduction var mı?)"
curl -fsS -H "$H" "$BASE/api/microsoft/automation/v2.0/companies($CID)/users?\$expand=userPermissions" \
 | python3 -c "import sys,json
for u in json.load(sys.stdin)['value']:
    ident=(u.get('userName','')+' '+u.get('contactEmail','')).lower()
    if 'dynops' in ident or 'badenatural' in ident:
        ps=[p.get('roleId') for p in u.get('userPermissions',[])]
        print('  ',u.get('userName'),u.get('contactEmail'),'->',ps)
        print('   BadeProduction yetkisi:', 'VAR' if any('BADE' in (p or '').upper() or 'PRODUCTION' in (p or '').upper() for p in ps) else 'YOK  <-- rapor 60150 çalışmaz')"
echo; echo "== Son 5 baskı işi (BC kuyruğu) — LP000025 için satır yoksa hata kuyruğa girmeden oluştu"
curl -fsS -H "$H" "$BASE/api/dynops/warehouse/v2.0/companies($CID)/printJobs?\$orderby=createdAt%20desc&\$top=5&\$select=jobId,sourceDoc,reportId,printerId,format,status,createdAt,lastError" \
 | python3 -c "import sys,json
for j in json.load(sys.stdin)['value']:
    print('  ',j['createdAt'],j['sourceDoc'],j['reportId'],j['printerId'],j['format'],j['status'],(j.get('lastError') or '')[:120])"
