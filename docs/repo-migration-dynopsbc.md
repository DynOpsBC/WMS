# Repo Migration → `DynOpsBC/BCWMSApp`

Eski: `https://github.com/celandeniz/BCWMSApp` (kişisel hesap, arşiv).
Yeni: `https://github.com/DynOpsBC/BCWMSApp` (organizasyon, canonical).

Migration kopya tipindedir — eski repo silinmez, redirect kurulmaz.
Tüm geliştirme yeni URL'e taşınır.

## Adım 0 — Hedef repo (GitHub web UI)

1. https://github.com/organizations/DynOpsBC/repositories/new
2. Name: `BCWMSApp`
3. Visibility: **Private** (CI secrets + Azure config içerir)
4. **Init etme** — README/.gitignore/license boş bırak
5. Create

## Adım 1 — History + tags push (local)

Local repo'da `dynops` remote zaten eklendi:

```bash
cd /Users/denizcelan/Documents/ClaudeCode/BCWMSApp
git remote -v
# origin → celandeniz (eski)
# dynops → DynOpsBC (yeni)

# Tüm branch'ler + tag'ler
git push -u dynops --all
git push dynops --tags
```

`push --all` 33+ branch (main + dependabot/* hepsi) gönderir.
`--tags` annotated/lightweight her ikisini gönderir.

## Adım 2 — Remote swap (origin canonical)

```bash
git remote rename origin celandeniz-archive
git remote rename dynops origin
# main upstream'ini yeni origin'e bind
git branch --set-upstream-to=origin/main main

# Verify
git remote -v
# celandeniz-archive → ... (read-only, isteğe bağlı silinebilir)
# origin → DynOpsBC/BCWMSApp.git ✓
```

## Adım 3 — GitHub-tarafı yapılandırma (yeni repo)

Eski repo'da kurulmuş ve YENI repoya elle taşınmalı:

### 3a. Secrets (Settings → Secrets and variables → Actions)

| Eski adı | Açıklama |
|---|---|
| `AZURE_CREDENTIALS` | Azure SP JSON — push-relay + licensing deploy için |
| `AZURE_FUNCTIONAPP_PUBLISH_PROFILE_*` | Function App publish profile (her ortam için) |
| `LICENSE_ADMIN_TOKEN` | `licensing-service`'in admin endpoint koruması |
| `FCM_SERVICE_ACCOUNT_JSON` | Push-relay Firebase admin JSON |
| `GITHUB_TOKEN` | Otomatik gelir, dokunmaya gerek yok |

> Eski celandeniz/BCWMSApp'te Settings → Secrets'ı aç, her birini değer
> kopyalama YAPMADAN (mask edilmiş) yeni repo'da aynı adla recreate et.
> Hangi secrets'in mevcut olduğunu görmek için ad listesi yeterli.

### 3b. Environments

`production`, `staging` environment'lar varsa Settings → Environments
altında yeniden oluştur. Protection rules (required reviewer, wait timer)
manuel kopyalanır.

### 3c. Branch protection

Settings → Branches → `main`:
- Require pull request reviews before merging (1+ reviewer)
- Require status checks: `android`, `web`, `push-relay`, `licensing`,
  `customer-portal` (workflow `test-full.yml` job'ları)
- Require branches to be up to date before merging
- Include administrators

### 3d. Webhooks

Eski repoda Azure webhook'u, dependabot, vs. varsa Settings →
Webhooks'tan recreate. Bu commit'i izleyen bir Azure deployment varsa
sırf URL değişikliği için yeni webhook kurulmalı.

### 3e. Dependabot

`.github/dependabot.yml` repo'da mevcut. Yeni repoda otomatik aktive olur.
14 açık dependabot PR (vite 5→8, AGP 9, ktor 3, vb.) eski repo'da kalır —
yeni repoda dependabot yeniden tarayıp yeni PR'lar açar (bazıları eş
zamanlı kalır, manuel review gerek).

## Adım 4 — Tüketici taraflarını güncelle

### Local clone'lar (her geliştirici)

```bash
git remote set-url origin https://github.com/DynOpsBC/BCWMSApp.git
git fetch origin
git branch --set-upstream-to=origin/main main
```

### CI çıkışları

`releases/` veya GitHub Pages URL'leri varsa kontrol et. `release.yml`
workflow'unda `gh release create` kullanılıyorsa `GITHUB_REPOSITORY`
otomatik yeni adı alır, manuel iş yok.

### Azure deployment job'ları

`azure-deploy.yml` veya CI içindeki Azure CLI komutları varsa:
- Function App tag'leri (sourceRepoUrl) yeni URL'e güncellenmeli
- Application Insights link'lerinde repo URL'i deprecated kalır

### Müşteri doc + Print Bridge

`docs/print-bridge-setup.md`, `docs/setup-runbook.md` içinde
github.com/celandeniz/BCWMSApp linkleri varsa update et:

```bash
grep -rl "celandeniz/BCWMSApp" docs/ web/ android/ \
  | xargs sed -i '' 's|celandeniz/BCWMSApp|DynOpsBC/BCWMSApp|g'
```

(Mevcut sed komutu test edilmeli — body'de string varsa replace olur.)

## Adım 5 — Eski repo'yu arşivle (opsiyonel)

`celandeniz/BCWMSApp` ileri geliştirme almasın diye:
- Settings → General → Archive this repository → ✓
- Read-only mod, yeni issue/PR/push reddedilir
- 301 redirect kurulmaz (GitHub archive yapmaz)
- README'ye en üste banner: "→ Moved to DynOpsBC/BCWMSApp"

## Doğrulama

```bash
git ls-remote dynops main      # SHA = local main'in SHA'sı olmalı
git ls-remote --tags dynops    # tüm tag'ler görünmeli
git fetch dynops --dry-run     # error yok

cd web && pnpm exec playwright test  # baseURL değişmedi, OK
./tools/run-all-tests.sh --quick      # 7/7 PASS olmalı
```

## Rollback

Yeni repo'da bir şey ters giderse (CI ayar eksik, secrets yanlış):
- `dynops` remote'una push edilmiş zarar verici değil — silmeden bırakılabilir
- `origin` (celandeniz) aktif, push'lar oraya devam edebilir
- Yeni repo'yu Settings → Delete this repository ile sil, sonra recreate

> **Önemli:** `git push --force --all` ile yeni repo'ya force push YAPMA.
> Branch protection devreye girdikten sonra force-push reddedilir + tarihçe
> tehlikeye atılır.

## Aksiyon takvimi

| Adım | Sorumlu | Tahmini süre |
|------|---------|--------------|
| 0. Hedef repo oluştur (GitHub UI) | denizcelan | 1 dk |
| 1. `git push -u dynops --all` + `--tags` | Claude/CI | 2-5 dk |
| 2. Remote swap (origin → dynops) | Claude | 30 sn |
| 3. Secrets/env/branch/webhook config | denizcelan | 15-30 dk |
| 4. Tüketici URL update'leri | denizcelan + Claude | 10 dk |
| 5. Eski repo archive | denizcelan | 1 dk |
