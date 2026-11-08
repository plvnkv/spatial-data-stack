# Spatial Data Stack

Внутрішня GIS відділу на одному сервері Ubuntu Server 26.04 LTS. k3s запускає платформу, а Argo CD синхронізує окремі Helm-застосунки з GitHub. GeoNode керує правами в порталі та інтегрується з GeoServer. Martin і TiTiler публікують спільний каталог векторних і растрових тайлів для LAN. PostGIS та RustFS доступні всередині кластера.

Джерело за замовчуванням — [plvnkv/spatial-data-stack](https://github.com/plvnkv/spatial-data-stack), гілка `main`. Для іншого джерела задайте `repo_url` і `branch` у конфігурації майданчика.

Після розгортання відкрийте портал за адресою з поля `geonode_host` у `site.json`. [Перший вхід і робота з GeoNode](docs/runbooks/04-geonode-user-guide.md)

## Runbooks

1. [Розгортання з нуля](docs/runbooks/01-deploy-from-scratch.md)
2. [Публікація і перевірка сервісів](docs/runbooks/02-publish-and-verify.md)
3. [Оновлення, резервування й відновлення](docs/runbooks/03-recovery-and-upgrades.md)
4. [Перший вхід, карти та публікація в GeoNode](docs/runbooks/04-geonode-user-guide.md)

[Погоджений дизайн](docs/superpowers/specs/2026-11-08-single-node-gis-design.md)

## Локальна перевірка

```bash
tests/render.sh all
python3 -m unittest discover -s tests
```

Для рендерингу потрібні Helm і ripgrep. Застосування YAML і перевірку з робочого місця виконуйте за runbooks.
