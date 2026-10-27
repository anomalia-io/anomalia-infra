# anomalia-infra

Infraestructura como código (IaC) de **Anomalia**: despliegue, actualización y destrucción del
stack de observabilidad con **Ansible**.

> El **backend** (`anomalia-backend`) no necesita clonarse a mano: si no existe un checkout
> hermano `../anomalia-backend`, este repo **clona automáticamente** la última release publicada
> del backend durante el deploy.

## 👤 Para Usuario Final (instalar Anomalia)

Este es el repo que ejecute para tener el stack corriendo. Flujo completo:

### 1. Prerequisites (validar antes de empezar)
- Linux: Debian 11/12, Ubuntu 20.04/22.04/24.04 LTS, o RHEL 8/9
- Arquitectura: x86_64 o arm64
- systemd como init system
- Docker CE **o** Podman rootful (con socket en grupo `docker`)
- Python 3 en `/usr/bin/python3`
- `ansible-core` >= 2.10 en el nodo de control
- `openssl` disponible
- usuario `anomalia` con `sudo` + miembro de `docker`/`wheel`

### 2. Despliegue
```bash
git clone https://github.com/anomalia-io/anomalia-infra.git
cd anomalia-infra
cp inventory.ini.example inventory.ini
$EDITOR inventory.ini          # editá las IPs de tus nodos (topología flexible)
./scripts/deploy.sh            # despliega todo el stack
```

**Qué despliega automáticamente:**
- VictoriaMetrics, VictoriaLogs, VictoriaTraces
- Pyroscope, vmagent, vmauth, Alertmanager
- vmalert (por-tenant o global según config)
- Backend FastAPI + Parses
- Firewall rules (iptables auto-detectado o firewalld rich rules)
- Certificados TLS (role `certs`, idempotente, `anomalia.local` por defecto)

### 3. Accesos después de deploy
| Servicio | Puerto | TLS | URL |
|----------|--------|-----|-----|
| Gateway HTTP | 80 | No | `http://anomalia.local` o IP del host |
| Gateway HTTPS | 443 | Sí | `https://anomalia.local` (sustituí certs/roles/certs) |
| Métricas (vmagent) | 8000 | No | `http://<IP>:8000/metrics` |
| Health check | 8000 | No | `http://<IP>:8000/healthz` |

### 4. Flujo después de cambiar código (OBLIGATORIO)
Según SSD protocol (`specs/013 §3.7`, `AGENTS.md §3.7`):
```bash
./scripts/deploy.sh --yes     # o los playbooks directamente:
ansible-playbook -i inventory.ini destroy-infra.yml && \
ansible-playbook -i inventory.ini deploy-infra.yml
```
*Requerido después de modificar código en backend/mobile/infra. NO necesario si solo
cambias docs/specs/AGENTS.md en anomalyia-meta.*

### 5. Destroy (limpieza completa)
```bash
ansible-playbook -i inventory.ini destroy-infra.yml
```
*Retira firewall, units, contenedores, volúmenes. **Siempre conserva**: imágenes base
(`postgres`, `ollama`) y `/opt/anomalia/certs`. No ejecuta `image prune -a` global.*

## 👨‍💻 Para Contribuidor/Developer

Modificás playbooks, roles, tasks o variables de inventario. Flujo SSD + Ansible:

### 1. Syntax Check (siempre antes de modificar o commitear)
```bash
ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check
ansible-playbook -i inventory.ini destroy-infra.yml --syntax-check
```

### 2. Invariantes SSD (spec 013 §2-4)
- Groups siempre con `groups.get('X', [])` NUNCA `groups['X']`
- Cada unit condicionada a su grupo: `when: inventory_hostname in groups.get('<grupo>', [])`
- Idempotencia: `state=present`/`state=started`/`state=enabled` son la norma
- Cross-refs: `hostvars[groups['X'][0]]` con fallback `*_ip | default(ansible_host) | default('127.0.0.1')`
- `StartLimitIntervalSec=0` y `After=network-online.target` en templates `.service.j2`
- `vault`/`no hardcodeo` de credenciales (usar `lookup('env', ...)` o Ansible Vault)

### 3. Topología flexible
- Un host puede pertenecer a múltiples grupos
- `inventory.ini` es la **única fuente de verdad**
- No asumir layout monolítico "todos en un solo host"

### 4. Commiteo de cambios en playbooks/roles
```bash
# 1. Modificar role/template en roles/ o tareas raíz
# 2. Syntax check (SIEMPRE!)
ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check
# 3. Probar en entorno controlado (o con --check)
ansible-playbook -i inventory.ini deploy-infra.yml --check
# 4. Commit con firma SSH
git add .
git commit -S -m "infra: <descripción>"
git push origin main
```

### 5. Consideraciones adicionales
- `ANOMALIA_RUN_WORKERS=false` fijo en contenedor TLS (`docker-compose.yml.j2`)
- `WorkerSupervisor` con `pg_try_advisory_lock(0x414E4F53)` - único executor único
- Heartbeat cada 15s, `_recover_orphans` si heartbeat_at stale
- `deploy-infra.yml` incluye post-task idempotente que re-sincroniza `admin_password`
- Roles `victoria_firewall` detecta automáticamente iptables vs firewalld
- `change-me-secret`, `anomal_password`, `admin_password` = riesgo aceptado (spec 006)

### 6. Stack
- **Ansible** (solo módulos `ansible.builtin`; sin colecciones externas)
- Ecosistema **Victoria**: VictoriaMetrics, VictoriaLogs, VictoriaTraces, vmagent, vmauth, vmalert, Alertmanager
- **Parses** (Perses) y **Pyroscope**
- Contenedores: **Docker CE** o **Podman rootful** (Compose v1/v2 o `podman-compose`)

## Uso (resumen)

```bash
# Desplegar (verifica sintaxis, clona el backend y aplica el stack)
./scripts/deploy.sh

# Redeploy sin confirmación destructiva
./scripts/deploy.sh --yes

# Verificar sintaxis manualmente
ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check

# Destruir
ansible-playbook -i inventory.ini destroy-infra.yml
```

> El role `backend` usa el checkout hermano `../anomalia-backend` si existe; si no, **clona
> automáticamente** la última release publicada de `anomalia-backend`. Para forzar una fuente:
> `-e anomalia_backend_src=/ruta` (checkout local) o `-e anomalia_backend_ref=main|vX.Y.Z`
> (rama/tag a clonar).

## Topología flexible (detalle)

La topología se decide **solo en `inventory.ini`**: cada grupo (`vlogs_*_nodes`, `vm_*_nodes`,
`vt_*_nodes`, `pyroscope_nodes`, `vmauth_nodes`, `vmagent_nodes`, `alertmanager_nodes`,
`vmalert_nodes`, `backend_nodes`, `parses_nodes`) define las IPs; un host puede pertenecer a
varios grupos. Cada unidad systemd se despliega solo en los hosts de su grupo.

## Aislamiento L4 (detalle)

El role `victoria_firewall` restringe los puertos de lectura (`8401`, `8481`, `8491`, `4040`) con
rich rules de `firewalld` o una cadena `iptables` `ANOMALIA_VICTORIA_READ`. Palancas:
`victoria_firewall_enabled` (default `true`) y `victoria_firewall_allowed_sources`.

## Licencia

[Apache-2.0](./LICENSE)
