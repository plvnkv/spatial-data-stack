# Публікація і перевірка сервісів

## Векторний шар

1. Завантажте [контрольний GeoJSON](../../tests/fixtures/sample-vector.geojson) у GeoNode як користувач із правом публікації. Перевірте, що GeoServer віддає ресурс у порталі.
2. Для Martin адміністратор додає таблицю до схеми `published` у базі `gis`. Якщо таблиця створена іншою роллю, явно надайте `SELECT` ролі `martin`. Працівники звертаються до Martin через HTTPS.
3. Додайте запис у `clusters/single-node/values/martin.yaml` і злийте PR у гілку розгортання.

```yaml
tables:
  sample-vector:
    schema: published
    table: sample_vector
    geometry_column: geom
    srid: 4326
```

Перевірте `https://vector.example.internal/catalog` і тайл для координат, які перетинають шар. Наприклад:

```bash
curl -fsS https://vector.example.internal/sample-vector/0/0/0 -o /tmp/sample.mvt
test -s /tmp/sample.mvt
```

## Растровий шар

1. Підготуйте COG, наприклад `gdal_translate -of COG input.tif sample.tif`.
2. Підключіть RustFS через адміністративний тунель. На сервері відкрийте `sudo k3s kubectl -n gis port-forward svc/rustfs-svc 9000:9000`. Для віддаленого клієнта додайте SSH-тунель. Підключіться до S3 за допомогою профілю з обліковими даними `cog-writer`.

```bash
aws --profile gis-cog-writer --endpoint-url http://127.0.0.1:9000 \
  s3 cp sample.tif s3://cog/samples/sample.tif
```

3. Додайте запис до `clusters/single-node/values/titiler.yaml` через PR.

```yaml
assets:
  sample-raster: samples/sample.tif
```

4. Перевірте `https://raster.example.internal/catalog`, запит тайла та відмову для стороннього URL.

```bash
curl -fsS 'https://raster.example.internal/cog/tiles/WebMercatorQuad/0/0/0.png?asset=sample-raster' -o /tmp/sample.png
test -s /tmp/sample.png
curl -sS -o /dev/null -w '%{http_code}\n' \
  'https://raster.example.internal/cog/info?asset=sample-raster&url=https://example.org/file.tif'
```

Останній запит має повернути 400. Невідомий ідентифікатор має повернути 404.

## Приймання

Після публікації двох контрольних джерел запустіть з робочого місця `tests/smoke.sh site.json all`. Права в порталі й доступність службових портів перевірте окремо за списком нижче.

- З робочого місця відкрийте три HTTPS endpoints з перевіркою CA. Перевірте недоступність портів 22, 6443, 5432, 9000 та 9001 з робочої мережі.
- З двома обліковими записами GeoNode перевірте дозволений і заборонений ресурс у порталі та на відповідному GeoServer endpoint. Спільний каталог Martin і TiTiler має відкриватися незалежно від сеансу GeoNode.
- З адреси поза дозволеною LAN перевірте блокування HTTPS endpoints.
- Після перезавантаження тестового вузла повторіть запити до контрольного вектора й растра.
