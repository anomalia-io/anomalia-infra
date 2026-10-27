# anomalia-infra

Infraestructura como código (IaC) de **Anomalia**: despliegue, actualización y destrucción del
stack de observabilidad con **Ansible**.

> El **backend** (`anomalia-backend`) no necesita clonarse a mano: si no existe un checkout
> hermano `../anomalia-backend`, este repo **clona automáticamente** la última release publicada
> del backend durante el despliegue.

## 👤 Para Usuario Final (instalar Anomalia)

Este es el repo que ejecutar para tener el stack corriendo. Flujo completo:

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

## Licencia

[Apache-2.0](./LICENSE)