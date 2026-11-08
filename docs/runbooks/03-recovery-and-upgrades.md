# Оновлення, резервування й відновлення

## Оновлення

1. Збережіть поточний Git commit і перевірте відновлювану резервну копію перед оновленням PostgreSQL, GeoNode, GeoServer чи RustFS.
2. Підготуйте PR зі зміною чарту або образу. Перегляньте згенеровані ресурси, сумісність версій і міграцій. Спочатку перевірте оновлення на окремому вузлі.
3. Після злиття перевірте стан Argo CD і [контрольні запити](02-publish-and-verify.md). Для конфігураційної регресії скасуйте Git commit. Якщо міграція змінює схему несумісно, відновіть попередню ревізію разом із копією даних.

## Зняти узгоджену копію

Виділіть вікно обслуговування. Зупиніть завантаження, фонові завдання й зовнішні записи в S3 та PostGIS. Призупиніть автоматичне відновлення масштабування в Argo CD на час операції. Зафіксуйте ревізію Git, час копії та версії образів. Команди запускайте з адміністративної машини. Каталог `BACKUP` має бути захищений і скопійований на окремий носій або сервер.

```bash
umask 077
BACKUP=/path/to/backup
mkdir -p "$BACKUP"
sudo k3s kubectl -n gis exec postgis-0 -- sh -ec \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h 127.0.0.1 -U postgres -Fc geonode' > "$BACKUP/geonode.dump"
sudo k3s kubectl -n gis exec postgis-0 -- sh -ec \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h 127.0.0.1 -U postgres -Fc gis' > "$BACKUP/gis.dump"
```

Скопіюйте об’єкти бакета `cog` через адміністративний тунель з [runbook публікації](02-publish-and-verify.md). Збережіть перелік ключів, контрольні суми та параметри політик. Для копії PVC змонтуйте `geonode-statics` і `geoserver-data` до тимчасового адміністративного pod у режимі read-only та виконайте `kubectl exec` із `tar -czf - -C /mount .` для кожного тому окремо. Збережіть права файлів, включно з маркерами ініціалізації.

Покладіть `site.json` і матеріал Secrets до зашифрованого сховища. Перевірте читабельність архівів і запишіть SHA-256. Відновіть роботу після завершення копіювання.

## Відновити прикладні дані на чистому вузлі

1. Підготуйте новий вузол за [runbook розгортання](01-deploy-from-scratch.md). Перейдіть на Git revision копії. Запустіть bootstrap з прапором `--without-applications`, щоб підготувати k3s, Argo CD та Secrets без запуску GIS. Тримайте GIS ingress закритим для працівників.
2. Встановіть Helm на адміністративній машині. Застосуйте сховища й маніфести PVC порталу в тестованій ревізії. Дочекайтеся завершення обох Jobs перед відновленням.

   ```bash
   for app in storage postgis rustfs; do
     helm template "$app" "charts/$app" -n gis -f "clusters/single-node/values/$app.yaml" --skip-tests |
       sudo k3s kubectl -n gis apply -f -
   done
   sudo k3s kubectl -n gis wait --for=condition=complete job/postgis-init job/rustfs-init --timeout=10m
   helm template geonode charts/geonode -n gis -f clusters/single-node/values/geonode.yaml \
     --show-only templates/services.yaml | sudo k3s kubectl -n gis apply -f -
   ```
3. Відновіть обидві бази в порожні цільові бази із запущеними ролями. Для копії з цього профілю виконайте `pg_restore --clean --if-exists --exit-on-error` від адміністратора після перевірки назви бази та адреси нового вузла. Завантажте COG у RustFS. Відновіть архіви PVC через тимчасовий pod із write-доступом і збереженням власників.
4. Повторіть bootstrap без `--without-applications` та дочекайтеся синхронізації GIS-застосунків. Перевірте їхній статус, права двох контрольних користувачів і контрольні тайли. Відкрийте доступ із LAN після проходження перевірок.

Для відновлення самого кластера зупиніть k3s перед копіюванням SQLite. Збережіть каталог `/var/lib/rancher/k3s/server/db`, `/var/lib/rancher/k3s/server/token` і конфігурацію сервера разом. Томи прикладних даних відновлюються окремо. [Процедура відновлення k3s](https://docs.k3s.io/datastore/backup-restore)
