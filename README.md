# anomalia-infra

Infraestructura como código (IaC) de **Anomalia**: despliegue, actualización y destrucción del
stack de observabilidad con **Ansible**.

> El **backend** (`anomalia-backend`) no necesita clonarse a mano: si no existe un checkout
> hermano `../anomalia-backend`, este repo **clona automáticamente** la última release publicada
> del backend durante el deploy.

## Quickstart (instalación en tus servidores)

```bash
# 1. Clonar este repo
git clone https://github.com/anomalia-io/anomalia-infra.git
cd anomalia-infra

# 2. Crear tu inventario y editar las IPs (topología flexible)
cp inventory.ini.example inventory.ini
$EDITOR inventory.ini

# 3. Desplegar (requiere sudo en los nodos)
ansible-playbook -i inventory.ini deploy-infra.yml
```

Una instalación en una sola máquina es el caso más simple: en `inventory.ini` dejá `localhost`
en todos los grupos (ya viene así en el ejemplo).

### Requisitos

- Nodo de control: `ansible-core` >= 2.10, `openssl`, `git`.
- Nodos destino: systemd, Docker CE o Podman **rootful**, Compose v1/v2 o `podman-compose`.
- Plataformas: Debian 11/12, Ubuntu 20.04/22.04/24.04, RHEL 8/9 y derivados; `x86_64`/`arm64`.

## Documentación

- [Despliegue de infraestructura con Ansible](docs/ansible-deployment.md) — comandos, roles,
  topología flexible, aislamiento L4.
- [Runner self-hosted (mantenedor)](docs/self-hosted-runner.md) — deploy automatizado por release
  en una máquina propia. **Solo relevante si tenés tu propio runner**; para uso normal alcanza con
  el deploy local del Quickstart.

## Stack

- **Ansible** (solo módulos `ansible.builtin`; sin colecciones externas)
- Ecosistema **Victoria**: VictoriaMetrics, VictoriaLogs, VictoriaTraces, vmagent, vmauth, vmalert, Alertmanager
- **Parses** (Perses) y **Pyroscope**
- Contenedores: **Docker CE** o **Podman rootful** (Compose v1/v2 o `podman-compose`)

## Estructura

```
roles/                 # backend, certs, parses, vmauth, vmalert, victoria_*, victoria_firewall, ...
tasks/                 # detect_container_stack.yml
deploy-infra.yml       # despliegue completo
destroy-infra.yml      # destrucción limpia
install-binaries.yml
sync-scrapes.yml
sync-vmalert-rules.yml
inventory.ini.example  # plantilla de inventario (copiala a inventory.ini)
docs/                  # documentación del repo
```

## Requisitos

- `ansible-core` >= 2.10
- `openssl` (generación de secretos/certs)
- En los nodos: systemd, Docker/Podman rootful, Compose

## Uso

```bash
# Verificar sintaxis
ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check

# Desplegar
ansible-playbook -i inventory.ini deploy-infra.yml

# Destruir
ansible-playbook -i inventory.ini destroy-infra.yml
```

> El role `backend` usa el checkout hermano `../anomalia-backend` si existe; si no, **clona
> automáticamente** la última release publicada de `anomalia-backend`. Para forzar una fuente:
> `-e anomalia_backend_src=/ruta` (checkout local) o `-e anomalia_backend_ref=main|vX.Y.Z`
> (rama/tag a clonar).

## Topología flexible

La topología se decide **solo en `inventory.ini`**: cada grupo (`vlogs_*_nodes`, `vm_*_nodes`,
`vt_*_nodes`, `pyroscope_nodes`, `vmauth_nodes`, `vmagent_nodes`, `alertmanager_nodes`,
`vmalert_nodes`, `backend_nodes`, `parses_nodes`) define las IPs; un host puede pertenecer a
varios grupos. Cada unidad systemd se despliega solo en los hosts de su grupo.

## Aislamiento L4

El role `victoria_firewall` restringe los puertos de lectura (`8401`, `8481`, `8491`, `4040`) con
rich rules de `firewalld` o una cadena `iptables` `ANOMALIA_VICTORIA_READ`. Palancas:
`victoria_firewall_enabled` (default `true`) y `victoria_firewall_allowed_sources`.

## Licencia

[Apache-2.0](./LICENSE)
