# Single-node GIS GitOps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal** — Розгорнути внутрішню GIS відділу з чистої Ubuntu VM та відтворити її після втрати вузла.

**Architecture** — Bootstrap встановлює k3s і Argo CD та реєструє кореневий Application. Дочірні Applications рендерять Helm, зберігають стан на постійних томах і перевіряють готовність своїх залежностей.

**Tech Stack** — Ubuntu Server 26.04 LTS, GitHub Actions, k3s, Traefik, Argo CD, Helm, GeoNode, GeoServer, PostGIS, RustFS, Martin, TiTiler.

**Spec** — [Дизайн](../specs/2026-11-08-single-node-gis-design.md).

## Global Constraints

- Один вузол. Ubuntu Server 26.04 LTS, amd64 як профіль перевірки.
- Вихідний HTTPS із сервера до GitHub, реєстрів і джерел чартів. CI працює поза LAN без kubeconfig.
- HTTPS у LAN з довірою до внутрішнього CA. SSH, Kubernetes API та Argo CD доступні адміністраторам.
- PostGIS доступний авторизованим компонентам кластера. Martin і TiTiler публікують спільний каталог. Права GeoNode діють у порталі та його GeoServer.
- Git містить декларативну конфігурацію і посилання на Secrets. Реальні ключі та паролі надходять ззовні.
- Збереження PVC при перевстановленні, зовнішні копії та перевірене відновлення. Версії образів, чартів і bootstrap-інструментів зафіксовані.
- Ініціалізувати локальний Git перед першим комітом. GitHub URL і гілка задаються оператором.

## Review Focus

- Повторний bootstrap після часткової невдачі відновлює запуск без заміни Secrets.
- Тимчасова недоступність PostGIS/RustFS не залишає частково ініціалізовані дані.
- Зникнення маніфесту з Git або видалення Application не видаляє дані.
- Підміна ідентифікатора растра чи передача URL не відкриває сторонній ресурс.
- Права GeoNode переживають відновлення, а відновлені вектор і COG читаються з іншого вузла.

---

## Карта файлів

| Шлях | Відповідальність |
| --- | --- |
| `bootstrap/install.sh`, `bootstrap/versions.env` | Точка входу та версії інструментів |
| `clusters/single-node/{root.yaml,project.yaml,applications/,values/}` | Шаблон кореня, обмеження проєкту, дочірні Applications і значення інсталяції |
| `charts/{storage,postgis,rustfs,geonode,martin,titiler}/` | Незалежні одиниці рендерингу та оновлення |
| `services/titiler/{app.py,Dockerfile,requirements.lock}` | Растровий API з дозволеним каталогом |
| `.github/workflows/{validate.yml,titiler-image.yml}` | Перевірка PR та публікація власного образу |
| `tests/{render.sh,smoke.sh,fixtures/}` | Перевірка маніфестів і наскрізні сценарії |
| `README.md`, `docs/{publish,operations,recovery}.md` | Інсталяція, публікація, оновлення й відновлення |

## Завдання 1. Bootstrap і контракт GitOps

**Інтерфейси** — `sudo bootstrap/install.sh --site FILE --secrets-dir DIR`. Конфігурація майданчика містить `repo_url`, `branch`, `lan_cidr`, `admin_cidr`, `data_dir`, `geonode_host`, `martin_host`, `titiler_host`. Файли секретів зчитуються без трасування та без передачі значень в аргументах команд. Значення Helm для майданчика надходять із каталогу values в Git. README описує узгодження мережевих параметрів між bootstrap і Helm.

- [ ] Додати `tests/render.sh bootstrap` та сценарій VM, що запускає bootstrap з недоступним репозиторієм, відновлює доступ і порівнює контрольні суми даних Secrets до та після повторного запуску.
- [ ] Запустити перевірки на чистій VM. Очікуваний початковий збій — відсутні bootstrap і кореневий Application.
- [ ] Зафіксувати сумісні версії k3s, Helm, Argo CD та валідатора. Реалізувати bootstrap, обмеження адміністративного доступу і кореневий Application. Обмежити редагування шляхів Argo CD адміністраторами GitHub. Секрети створювати за відсутності, ротацію описати окремо.
- [ ] Повторити сценарій. Очікувати `Synced` для кореня і незмінні Secrets. Запустити `bash -n bootstrap/install.sh tests/render.sh`.
- [ ] Коміт `feat: bootstrap the single-node GitOps cluster`.

## Завдання 2. Постійне сховище, PostGIS і RustFS

**Інтерфейси** — namespace `gis`, StorageClass `gis-local-retain`, внутрішні Services `postgis:5432` і `rustfs:9000`, бази `geonode` та `gis`, бакет `cog`. Службові Secrets `postgis-admin`, `geonode-db`, `geoserver-db`, `martin-db`, `rustfs-admin`, `titiler-s3` і `cog-writer`.

- [ ] Додати рендер-перевірки Retain, захисту PVC від prune/delete і ClusterIP для сховищ. Додати smoke-сценарій, який записує рядок і об’єкт, перезапускає компоненти та перечитує обидва. Додати повтор ініціалізації після тимчасово недоступного endpoint.
- [ ] Запустити `tests/render.sh storage`. Очікувати відсутні чарти сховищ.
- [ ] Налаштувати локальне виділення томів у `data_dir`, StatefulSet PostGIS і зафіксований upstream-чарт RustFS standalone. Перевірити сумісність образу RustFS і S3. Jobs після появи залежностей створюють бази, PostGIS extension, ролі, бакет і політики доступу. Використати окрему роль читання Martin і scoped read-only доступ TiTiler. Додати мережеву політику для бази.
- [ ] Запустити `tests/render.sh storage` і `tests/smoke.sh storage`. Перевірити перезапуск, повторну ініціалізацію, відхилення запису роллю Martin і збереження даних після видалення та повторного створення Application у тестовому кластері.
- [ ] Коміт `feat: provision durable PostGIS and RustFS storage`.

## Завдання 3. GeoNode і GeoServer

**Інтерфейси** — бази й Secrets із завдання 2. Портал на `https://geonode_host/`, GeoServer за `/geoserver/` на тому самому origin, із внутрішніми URL для сервісних викликів. TLS Secret `geonode-tls`.

- [ ] Додати `tests/smoke.sh geonode`. Після імпорту контрольного вектора користувач із дозволом читає ресурс, а другий користувач отримує відмову для ресурсу в порталі й на відповідному GeoServer endpoint.
- [ ] Запустити сценарій. Очікувати відсутні endpoint і ресурс.
- [ ] Вибрати спільно підтримувані образи GeoNode і GeoServer за upstream deployment обраного релізу. Перенести потрібні worker та broker, конфігурацію OAuth2 і GeoFence, міграції та початкову конфігурацію каталогу. Забезпечити збереження файлів і GeoServer data directory. Міграційний Job чекає доступу до БД, а rollout чекає успішних міграцій. Початковий deployment і повторна синхронізація використовують ті самі Secrets.
- [ ] Запустити `tests/render.sh geonode` та `tests/smoke.sh geonode`. Додатково перезапустити портал і перевірити той самий ресурс та права.
- [ ] Коміт `feat: deploy the GeoNode and GeoServer portal`.

## Завдання 4. Martin

**Інтерфейси** — `martin-db`, внутрішній PostGIS, `https://martin_host/`, TLS Secret `martin-tls`. Список джерел визначається у values, тестове джерело має ID `sample-vector`.

- [ ] Додати `tests/smoke.sh martin`. `/catalog` містить `sample-vector` і виключає контрольну непубліковану таблицю. Запит до контрольного тайла повертає 200 та непорожній MVT.
- [ ] Запустити сценарій. Очікувати відсутній endpoint.
- [ ] Створити Helm Application і конфіг Martin із вимкненим автоматичним виявленням джерел. Зберігати DSN у Secret, перевіряти готовність БД і додати HTTPS Ingress.
- [ ] Запустити `tests/render.sh martin` і `tests/smoke.sh martin`. Повторити запит незалежно від GeoNode-сеансу.
- [ ] Коміт `feat: publish selected PostGIS layers with Martin`.

## Завдання 5. TiTiler

**Інтерфейси** — `titiler-s3`, внутрішній RustFS, `https://titiler_host/`, TLS Secret `titiler-tls`. GET `/cog/tiles/WebMercatorQuad/{z}/{x}/{y}?asset=sample-raster`. Ключі дозволених COG задаються як відображення ID → ключ у бакеті `cog`.

- [ ] Додати тести клієнта і `tests/smoke.sh titiler`. Валідний ID дає 200 і непорожнє зображення. Невідомий ID дає 404. Запит із параметром `url`, без `asset` або зі шляхом замість ID отримує 4xx. Підставлений URL не доходить до GDAL.
- [ ] Запустити тести. Очікувати відсутні застосунок і маршрут.
- [ ] Реалізувати в `services/titiler/app.py` власну залежність шляху для TilerFactory. Збирати зафіксований TiTiler у GHCR, використовувати digest у Helm values і монтувати каталог із ConfigMap. Використати внутрішній S3 endpoint і облікові дані лише для читання. Звузити вихідний трафік до RustFS і DNS.
- [ ] Запустити тести застосунку, `tests/render.sh titiler` і `tests/smoke.sh titiler` з COG у RustFS. Перевірити запит з LAN після перезапуску.
- [ ] Коміт `feat: serve RustFS COG tiles with TiTiler`.

## Завдання 6. Інтеграція, CI і документація

**Інтерфейси** — `tests/render.sh all` рендерить усі Applications та їхні чарти з тестовими values. `tests/smoke.sh all` використовує конфігурацію майданчика та двох тестових користувачів із захищених файлів. Потрібна одноразова Ubuntu VM із доступом із тестової LAN.

- [ ] Додати CI-перевірку Helm lint, рендеру, schema validation для версії k3s, відсутності реальних секретів у fixtures та тестів TiTiler. Підтвердити, що помилковий тестовий маніфест ламає перевірку.
- [ ] З’єднати всі Applications у корені. Увімкнути автоматичну синхронізацію з retry. Відокремити порядок розгортання від перевірок готовності. Задокументувати випуск нового образу, безпечне оновлення, публікацію вектора та COG і налаштування TLS.
- [ ] На чистій Ubuntu VM виконати два bootstrap, дочекатися Healthy/Synced, виконати `tests/smoke.sh all`, перезавантажити вузол і повторити. З робочої мережі перевірити HTTPS і відмову для SQL, Argo CD, SSH, Kubernetes API та RustFS. Із сторонньої мережі перевірити обмеження GIS endpoints.
- [ ] Коміт `ci: verify the single-node GIS deployment`.

## Завдання 7. Відновлення на новому вузлі

**Інтерфейси** — `docs/recovery.md` визначає зашифрований набір копій поза вузлом, ідентифікатор Git revision, порядок відновлення та команди перевірки. Основний сценарій — новий кластер з Git і копій прикладних даних. Окремий сценарій — відновлення SQLite k3s із серверним токеном.

- [ ] Додати критерії recovery у `tests/smoke.sh recovery`. Після відновлення контрольні дані читаються через Martin і TiTiler, а матриця дозволів GeoNode збігається з початковою.
- [ ] На порожньому вузлі запустити перевірку до відновлення. Очікувати відсутні контрольні ресурси.
- [ ] Описати та виконати резервування з призупиненими записами. Зберегти PostgreSQL dumps, об’єкти й політики бакета, файли GeoNode, GeoServer data directory і матеріал bootstrap. На новому вузлі відновити Secrets і дані до відкриття ingress та запуску компонентів, що пишуть. Задокументувати фактичні дії й час пробного відновлення.
- [ ] Повторити `tests/smoke.sh recovery` і `tests/smoke.sh all` на новому вузлі. Перевірити публікацію нового вектора та COG після відновлення.
- [ ] Коміт `docs: verify off-node backup and recovery`.

## Технічні джерела

- [Argo CD sync phases and waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Конфігурація Martin](https://maplibre.org/martin/config-file/)
- [Налаштування залежності шляху в TiTiler](https://developmentseed.org/titiler/advanced/customization/)
