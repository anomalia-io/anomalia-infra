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

### Changed
- El workflow self-hosted usa `scripts/deploy.sh` y conserva `inventory.ini` y
  `.secrets/` entre corridas (`actions/checkout` con `clean: false`).

## [0.1.0] - 2026-10-20

### Added
- Initial import from the `anomalia-project` monorepo.
