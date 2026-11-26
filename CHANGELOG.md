# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `scripts/deploy.sh`: deploy unificado (local y runner) de infra + backend, con
  resolución de inventario, clonado del backend por SSH y guard destructivo.
- Token webhook AM ↔ Backend persistido en `.secrets/` cuando no hay
  `ALERTMANAGER_WEBHOOK_TOKEN` en el entorno.
- Gateway TLS con Nginx: TLS externo autofirmado o provisto y TLS interno
  separado para Parses.
- `scripts/deploy.sh --tls-only` y `deploy-tls.yml` para renovar certificados
  sin `down -v`; flags `--tls-mode`, `--hostname`, `--cert`, `--key`,
  `--tls-force`.
- Protección contra sobreescritura: un `external/fullchain.pem` sin el marcador
  `.managed-by-ansible` se conserva como certificado provisto aunque el modo sea
  `self_signed`; `--tls-force` lo reemplaza.
- `allocate-vmalert-port.yml`: asignación remota de puertos para unidades vmalert
  por-tenant, con marcador `VMALERT_FREE_PORT=` en el stdout.
- Relabel `tenant` derivado de `tenant_slug` en el template de vmagent, consumido
  por Alertmanager y el backend para cerrar firing huérfanas.

### Changed
- `scripts/deploy.sh` prepara una copia temporal del backend sin `.git`,
  `.opencode`, cachés, entornos virtuales ni `node_modules` antes de ejecutar
  Ansible, evitando copias recursivas de miles de artefactos locales.
- El workflow self-hosted usa `scripts/deploy.sh` y conserva `inventory.ini` y
  `.secrets/` entre corridas (`actions/checkout` con `clean: false`).
- El gateway FastAPI TLS fue reemplazado por Nginx; el único contenedor FastAPI
  es `anomalia_gw` en `:8000`.
- `install-binaries.yml` usa URLs directas de releases y versiones fijadas:
  VictoriaLogs `v1.54.0`, VictoriaMetrics `v1.157.0`, VictoriaTraces `v0.13.0`,
  Pyroscope `v2.4.4` y Alertmanager `v0.35.1` (Parses sigue en `latest`).
- Con `servicio=vmalert` y `gestionar_servicios=true`, `install-binaries.yml`
  descubre y reinicia **secuencialmente** las unidades vmalert por-tenant, sin
  tocar la unidad única cuando existen unidades por tenant.

## [0.1.0] - 2026-10-20

### Added
- Initial import from the `anomalia-project` monorepo.
