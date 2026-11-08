# Розгортання з нуля

## 1. Підготувати майданчик

- Ubuntu Server 26.04 LTS на фізичному сервері або VM. Для першої перевірки рекомендовано amd64. Забезпечте дискову ємність під базу, файли GeoNode, COG і робочі копії. На локальному provisioner розмір PVC є запитом ємності, тому перевіряйте вільне місце на файловій системі.
- Налаштуйте сталу IP-адресу, синхронізацію часу і вихідний HTTPS до GitHub, джерел k3s і Helm, реєстрів образів та чартів.
- Створіть внутрішні DNS-записи для GeoNode, Martin і TiTiler з IP цього вузла. Видайте TLS-сертифікати з відповідними SAN. Додайте кореневий CA до довірених на робочих місцях.
- На мережевому екрані дозвольте TCP 443 із LAN відділу, а TCP 22 і 6443 лише з адміністративної мережі. Перевірте SSH з адміністративної адреси до застосування правил. Забороніть вхід до службових портів. IP allowlist Traefik додатково обмежує GIS-маршрути.
- Підмонтуйте диск даних за сталим шляхом, наприклад `/srv/gis`, із записом у `/etc/fstab`. Перед bootstrap перевірте `findmnt /srv/gis` і `df -h /srv/gis`.
- Переконайтеся, що GitHub-гілка містить маніфести цього репозиторію, а адміністратори контролюють зміни шляхів Argo CD. Використовуйте PR і захист гілки.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git openssl python3
git clone https://github.com/plvnkv/spatial-data-stack
cd spatial-data-stack
cp bootstrap/site.example.json site.json
```

У `site.json` задайте DNS-імена, LAN CIDR, адміністративний CIDR, шлях диска та гілку. `admin_cidr` документує адміністративну мережу для налаштування зовнішнього екрана. Параметри томів і каталоги публікацій задаються в `clusters/single-node/values/`.

## 2. Підготувати секрети

Захищена директорія передає bootstrap по одному файлу на ключ Secret. Для паролів бази й адміністратора GeoServer використовуйте випадкові hex-рядки. Образи підставляють ці значення у DSN та XML. Згенеруйте секрети один раз і збережіть резервну копію в захищеному сховищі. Наповнюйте файли через `printf '%s'` або `openssl rand -hex 32 | tr -d '\n'`, щоб значення паролів не містили кінцевого переносу рядка.

| Директорія під `secrets/` | Файли |
| --- | --- |
| `gis/postgis-admin`, `gis/geonode-db`, `gis/geoserver-db`, `gis/martin-db` | `password`, окремий для кожної ролі |
| `gis/geonode-app` | `SECRET_KEY`, `ADMIN_PASSWORD`, `ADMIN_EMAIL`, `GEOSERVER_ADMIN_PASSWORD`, `OAUTH2_CLIENT_ID`, `OAUTH2_CLIENT_SECRET`, `OAUTH2_API_KEY`, `OIDC_RSA_PRIVATE_KEY` |
| `gis/rustfs-admin` | `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY` |
| `gis/titiler-s3`, `gis/cog-writer` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, окрема пара на кожен Secret |
| `gis/geonode-tls`, `gis/martin-tls`, `gis/titiler-tls` | `tls.crt` з ланцюжком та `tls.key` |
| `argocd/github-repo` | Для приватного репозиторію `type` зі значенням `git`, `url` із точним значенням `repo_url`, `username` і `password` із read-only токеном GitHub |

Наприклад, створення пароля адміністратора бази:

```bash
umask 077
mkdir -p secrets/gis/postgis-admin
openssl rand -hex 32 | tr -d '\n' > secrets/gis/postgis-admin/password
mkdir -p secrets/gis/geonode-app
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out secrets/gis/geonode-app/OIDC_RSA_PRIVATE_KEY
```

## 3. Запустити bootstrap

```bash
sudo bootstrap/install.sh --site site.json --secrets-dir secrets
sudo k3s kubectl -n argocd get applications
sudo k3s kubectl -n gis get pods,pvc,jobs
```

Коли всі дочірні застосунки мають `Synced` і `Healthy`, виконайте [перевірку з робочого місця](02-publish-and-verify.md). Повторний запуск із тим самим файлом майданчика зберігає наявні Secrets. Змінені значення секретів застосовуйте окремою процедурою ротації.

### Доступ до Argo CD

З Mac або іншої адміністративної машини відкрийте SSH-тунель. Потрібен SSH-обліковий запис на сервері з доступом до `sudo k3s kubectl`. Замініть `ubuntu` та IP на значення вашого сервера. Для тестової VM IP можна перевірити командою `multipass list`.

```bash
ssh -t -o ExitOnForwardFailure=yes -L 127.0.0.1:8080:127.0.0.1:8080 \
  ubuntu@192.168.252.5 \
  'sudo k3s kubectl -n argocd port-forward --address 127.0.0.1 svc/argocd-server 8080:443'
```

Залиште команду працювати й відкрийте [Argo CD](https://localhost:8080/). Для стандартної інсталяції Argo CD використовує власний TLS-сертифікат. Якщо браузер йому не довіряє, налаштуйте довірений сертифікат для Argo CD.

Для першого входу використайте ім’я `admin`. Початковий пароль можна прочитати на сервері в захищеному терміналі.

```bash
sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
printf '\n'
```

На Mac для тестової VM ту саму команду можна виконати через Multipass.

```bash
multipass exec gis-gitops-test -- sudo sh -c \
  'k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; printf "\n"'
```

Якщо початковий Secret уже видалено, використайте поточний пароль адміністратора. У розділі **Applications** відкрийте `gis-root` або конкретний застосунок і перегляньте **Sync Status** та **Health**. [Документація Argo CD](https://argo-cd.readthedocs.io/en/stable/getting_started/)

## 4. Діагностика першого запуску

| Симптом | Перевірка |
| --- | --- |
| Корінь має `ComparisonError` | `sudo k3s kubectl -n argocd describe application gis-root`. Перевірте гілку, URL і доступ GitHub. |
| PVC у `Pending` | `sudo k3s kubectl -n gis describe pvc <claim>`. Перевірте StorageClass, готовність вузла, pod-споживач і доступність диска. |
| Pod у `ImagePullBackOff` | `sudo k3s kubectl -n gis describe pod <pod>`. Перевірте тег, архітектуру образу та доступ до реєстру. |
| Ініціалізація застрягла | `sudo k3s kubectl -n gis get jobs` і `sudo k3s kubectl -n gis logs job/<job>`. Перевірте Secrets і readiness залежності перед повторною синхронізацією. |
| TLS або 403 | Перевірте DNS, SAN, довіру до CA і адресу клієнта, яку бачить Traefik. |
