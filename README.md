# Anomalía — Infraestructura

Infraestructura como código (Ansible) para desplegar el stack de observabilidad de **Anomalía**: VictoriaMetrics, VictoriaLogs, VictoriaTraces, Pyroscope, vmagent, vmauth, Alertmanager, vmalert, backend FastAPI, Parses y gateway TLS.

## 1. Elegí el inventario

El inventario es la única fuente de topología. Hay dos plantillas:

| Plantilla | Cuándo usarla | Resultado |
|---|---|---|
| `inventory.ini.local.example` | Probar en **una sola máquina** | Listo para copiar y ejecutar |
| `inventory.ini.multi.example` | **Implementación real** en varios servidores | Reemplazá cada `HOST` por la IP real |

```bash
git clone https://github.com/anomalia-io/anomalia-infra.git
cd anomalia-infra

# Prueba local
cp inventory.ini.local.example inventory.ini
./scripts/deploy.sh

# Implementación real (multi-servidor)
cp inventory.ini.multi.example inventory.ini
$EDITOR inventory.ini          # reemplazá HOST por IPs y credenciales SSH
./scripts/deploy.sh
```

En multi-servidor, un mismo host puede repetirse en varios grupos; usá el mismo alias y la misma IP en todas sus apariciones. No uses `ansible_connection=local` salvo que el servidor sea la propia máquina donde corre Ansible.

## 2. Prerrequisitos

### Nodo de control (donde corre Ansible)

- Linux con `ansible-core >= 2.10`, `git`, `openssl` y Python 3.
- Acceso SSH a los servidores remotos (o `ansible_connection=local` para prueba local).
- `sudo` en los nodos destino.

### Nodos destino

- Debian 11/12, Ubuntu 20.04/22.04/24.04 LTS o RHEL 8/9 derivados.
- `x86_64` o `arm64`, `systemd`.
- Docker CE o Podman rootful con Compose (`docker compose`, `docker-compose` o `podman-compose`).

El usuario de servicio `anomalia` lo crea el deploy.

## 3. Despliegue

```bash
./scripts/deploy.sh                                      # usa inventory.ini
./scripts/deploy.sh --inventory /ruta/inventory.ini      # otro inventario
./scripts/deploy.sh --backend-src ../anomalia-backend    # checkout local del backend
./scripts/deploy.sh --backend-ref main                   # rama/tag a clonar por SSH
```

Por defecto el wrapper clona `anomalia-backend` por SSH desde `main`; no descarga automáticamente la última release.

Opciones TLS habituales:

```bash
./scripts/deploy.sh --tls-mode self_signed --hostname anomalia.mi-dominio.com --tls-force
./scripts/deploy.sh --cert /ruta/fullchain.pem --key /ruta/privkey.pem
./scripts/deploy.sh --tls-only                  # solo renueva certificados
```

El certificado autofirmado usa por defecto la IP del host backend como CN/SAN, más `127.0.0.1`, `localhost` y `anomalia.local`. Para dominio propio, pasá `--hostname`.

## 4. Accesos después del deploy

| Servicio | Puerto | URL |
|---|---|---|
| Gateway HTTP | 80 | `http://<IP-del-backend>` (redirige a HTTPS si TLS activo) |
| Gateway HTTPS | 443 | `https://<IP-o-hostname-del-backend>` |
| Backend / health | 8000 | `http://<IP-del-backend>:8000/healthz` |
| vmagent | 8429 | `http://<IP-de-vmagent>:8429/metrics` |
| Nginx interno (Parses) | 8443 | Solo red de contenedores |

Para el QR móvil, abrí el panel desde la IP de la LAN; el QR usa el origen actual de la URL.

## 5. Actualizaciones y datos

El redeploy **conserva** `postgres_data` y `ollama_data`. Si querés borrar base de datos y modelos Ollama:

```bash
./scripts/deploy.sh --reset-data           # pide confirmación
./scripts/deploy.sh --reset-data --yes     # sin confirmación
```

También podés usar el playbook directo:

```bash
ansible-playbook -i inventory.ini deploy-infra.yml
ansible-playbook -i inventory.ini deploy-infra.yml -e anomalia_compose_destroy_volumes=true
```

En multi-servidor, el firewall permite automáticamente las IPs de todos los nodos del inventario. Si backend y Parses están en hosts distintos, se comunican por `backend_ip:backend_port` y `parses_ip:parses_port`; si comparten host, usan el DNS del bridge.

## 6. Destrucción

```bash
ansible-playbook -i inventory.ini destroy-infra.yml
```

Retira units, contenedores, redes, reglas de firewall y directorios de Anomalía. Conserva las imágenes base (`postgres`, `ollama`) y `/opt/anomalia/certs`.

## Documentación

- [Despliegue detallado con Ansible](docs/ansible-deployment.md)
- [Runner self-hosted](docs/self-hosted-runner.md)
- [Licencia del código](./LICENSE) — Apache-2.0
- [Licencia de la documentación](./LICENSE-DOCS) — CC BY-SA 4.0
