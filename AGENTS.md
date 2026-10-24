# AGENTS.md — anomalia-infra

Guía para agentes y desarrolladores que trabajen en **`anomalia-infra`**: la infraestructura
como código (Ansible) del stack de observabilidad de **Anomalia**.

> Este repo es parte del proyecto multi-repo **Anomalia** (`anomalia-io`). Las specs SSD y la
> gobernanza viven en el repo privado `anomalia-meta`. Trabajá **una sesión por repo**.

## Stack

- **Ansible** (playbooks y roles), sobre **systemd**.
- Plataformas: Debian 11/12, Ubuntu 20.04/22.04/24.04 LTS, RHEL 8/9 + derivados; `x86_64`/`arm64`.
- Contenedores: Docker CE o Podman rootful (Compose v1/v2 o `podman-compose`), abstraídos por facts `anomalia_*`.
- Firewall: firewalld (RHEL) o iptables (Debian/Ubuntu), auto-detectado por el role `victoria_firewall` con solo módulos `ansible.builtin`.
- Ecosistema Victoria: VictoriaMetrics, VictoriaLogs, VictoriaTraces, vmagent, vmalert, vmauth, Alertmanager, Pyroscope.

## Comandos

```bash
./scripts/deploy.sh                                                 # despliegue (infra + backend)
./scripts/deploy.sh --yes                                           # redeploy sin confirmación
ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check   # verificación de sintaxis
ansible-playbook -i inventory.ini deploy-infra.yml                  # despliegue manual
ansible-playbook -i inventory.ini destroy-infra.yml                 # destrucción
gitleaks dir .                                                      # escaneo de secretos (obligatorio)
```

`inventory.ini` **no se versiona** (ignorado); usá `inventory.ini.example` como plantilla.

## Invariantes (obligatorios)

- **El inventario es la única fuente de topología.** Quien instala coloca las IPs en los
  grupos (`vlogs_*_nodes`, `vm_*_nodes`, `vt_*_nodes`, `pyroscope_nodes`, `vmauth_nodes`,
  `vmagent_nodes`, `alertmanager_nodes`, `vmalert_nodes`, `backend_nodes`, `parses_nodes`);
  un mismo host puede pertenecer a cualquier combinación de grupos.
- **Cada unit systemd se despliega ÚNICAMENTE en los hosts de su grupo**
  (`inventory_hostname in groups.get('<grupo>', [])`). Ningún play/role asume layout monolítico.
- **Referencias cruzadas** vía `hostvars[groups['X'][0]]`, prefiriendo `*_ip` con fallback a
  `ansible_host` y `127.0.0.1`; `groups.get('X', [])` para tolerar grupos vacíos.
- **Idempotencia estricta** en toda task.
- **Auto-recuperación de units**: cada role systemd cierra con `systemd: state=started,
  enabled=yes` por unit (converge estado sin depender de handlers).
- **Orden de arranque**: templates con `After=network-online.target` + `Wants=network-online.target`
  y `StartLimitIntervalSec=0` en `[Unit]`.
- **Destroy completo**: `destroy-infra.yml` retira todo lo que crea el deploy, incluidas units
  derivadas por-tenant, sin hardcodear slugs ni hostnames.

Detalle completo en `specs/013-deployment-topology-and-idempotency.md` (repo `anomalia-meta`).

## Convenciones

- **Sin secretos**: nunca versionar credenciales. Referenciar por variable de entorno
  (`lookup('env', ...)`) o por archivos locales ignorados en `.secrets/` (allowlist
  de gitleaks por path). El deploy del token webhook usa env y cae a
  `.secrets/alertmanager_webhook_token`.
- **Commits firmados**: `commit.gpgsign=true` con SSH (heredado del `~/.gitconfig` global).
- **Un PR por repo**: si un cambio impacta otro repo, abrí una sesión en ese repo.

## Documentación

- [Despliegue con Ansible](docs/ansible-deployment.md)
- [Runner self-hosted](docs/self-hosted-runner.md)

## Enlaces

- Specs SSD y gobernanza: repo privado `anomalia-meta` (`specs/`).
- Backend desplegado: [`anomalia-backend`](https://github.com/anomalia-io/anomalia-backend).
