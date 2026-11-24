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

### Changed
- `scripts/deploy.sh` prepara una copia temporal del backend sin `.git`,
  `.opencode`, cachés, entornos virtuales ni `node_modules` antes de ejecutar
  Ansible, evitando copias recursivas de miles de artefactos locales.
- El workflow self-hosted usa `scripts/deploy.sh` y conserva `inventory.ini` y
  `.secrets/` entre corridas (`actions/checkout` con `clean: false`).
- El gateway FastAPI TLS fue reemplazado por Nginx; el único contenedor FastAPI
  es `anomalia_gw` en `:8000`.

## [0.1.0] - 2026-10-20

### Added
- Initial import from the `anomalia-project` monorepo.
