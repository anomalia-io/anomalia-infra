# Despliegue de Infraestructura (Ansible)

El aprovisionamiento, actualización y destrucción de la infraestructura de observabilidad de Anomalia se gestiona íntegramente mediante playbooks y roles de **Ansible** (`anomalia-infra/`).

Los playbooks raíz son `deploy-infra.yml` (stack completo), `deploy-tls.yml` (renovación de
certificados sin bajar volúmenes) y `destroy-infra.yml` (limpieza explícita). El wrapper
`./scripts/deploy.sh` es la forma recomendada de invocarlos: valida prerrequisitos e inventario,
prepara el checkout del backend y ejecuta el playbook correspondiente.

---

## 🛠️ Prerrequisitos de Plataforma

### Nodo de Control (Ansible Controller)
- **ansible-core** >= 2.10 (probado con `ansible 2.10.8`).
- **Sin dependencias externas:** El rol `victoria_firewall` utiliza exclusivamente módulos nativos de `ansible.builtin` (`firewall-cmd` para RHEL o reglas `iptables` para Debian/Ubuntu). No requiere colecciones adicionales.
- `openssl` para la generación de secretos compartidos.

### Nodos Destino (Managed Nodes)
- **Sistemas Operativos Soportados:** Debian 11/12, Ubuntu 20.04 / 22.04 / 24.04 LTS, RHEL 8/9 y derivados (Rocky / Alma / CentOS Stream).
- **Arquitectura:** `x86_64` (amd64) o `arm64` (aarch64).
- **Init System:** `systemd` obligatorio.
- **Contenedores:** Docker CE (socket activo, grupo `docker`) o Podman rootful, con soporte para `docker compose` (v2), `docker-compose` (v1) o `podman-compose`.

---

## 🚀 Comandos Clave de Operación

### 1. Verificación de Sintaxis
```bash
cd anomalia-infra
ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check
```

### 2. Despliegue Completo de la Plataforma
```bash
cd anomalia-infra
./scripts/deploy.sh
```

Elegí la plantilla según el caso: `inventory.ini.local.example` para prueba local
(en una sola máquina) o `inventory.ini.multi.example` para implementación real.
Copiá la que corresponda a `inventory.ini`.

El script unifica el flujo local y el del runner: valida prerrequisitos, resuelve
`inventory.ini`, usa el checkout local indicado por `--backend-src` o clona
`anomalia-backend` por SSH desde la rama `main` (configurable con `--backend-ref`),
verifica la sintaxis y ejecuta el deploy. Antes de invocar Ansible, prepara una copia
temporal del backend excluyendo `.git`, `.opencode`, cachés, entornos virtuales y
`node_modules`; así `ansible.builtin.copy` no recorre artefactos locales del
checkout. Los cambios sin commitear se conservan y la copia temporal se elimina
al finalizar.

Opciones del wrapper:

| Opción | Efecto |
|---|---|
| `--reset-data` | Borra volúmenes de PostgreSQL/Ollama; pide confirmación. |
| `-y`, `--yes` | No pide la confirmación de `--reset-data`. |
| `-i`, `--inventory PATH` | Usa otro inventario en lugar de `inventory.ini` del repo. |
| `-b`, `--backend-src PATH` | Usa un checkout local del backend en vez de clonar. |
| `-r`, `--backend-ref REF` | Rama/tag del clon SSH (default: `main`). |
| `--tls-mode MODE` | `self_signed`, `provided` o `disabled` (default: `self_signed`). |
| `--hostname NAME` | CN/SAN principal del certificado externo (default: IP del backend). |
| `--cert PATH`, `--key PATH` | Material provisto; implica `--tls-mode provided`. |
| `--tls-force` | Rota el material generado y permite cambiar el SAN. |
| `--tls-only` | Ejecuta solo `deploy-tls.yml` (no toca volúmenes). |

```bash
./scripts/deploy.sh --reset-data
./scripts/deploy.sh --reset-data --yes
./scripts/deploy.sh --backend-src ../anomalia-backend
./scripts/deploy.sh --backend-ref main
./scripts/deploy.sh --inventory /ruta/inventory.ini
./scripts/deploy.sh --tls-mode self_signed --hostname anomalia.mi-dominio.local --tls-force
./scripts/deploy.sh --cert /ruta/fullchain.pem --key /ruta/privkey.pem
./scripts/deploy.sh --tls-only
./scripts/deploy.sh --help
```

`deploy.sh` **siempre inyecta `-e certs_mode=<modo>`**. Por eso las variables TLS del
inventario (`certs_mode`, `certs_hostname`, `certs_external_cert`, `certs_external_key`)
solo se aplican cuando se invoca el playbook directamente. Un deploy completo ejecuta
`docker compose down --remove-orphans` conservando `postgres_data` y `ollama_data`.
Solo con `--reset-data` (o `-e anomalia_compose_destroy_volumes=true`) se usa `down -v`.

Equivalente manual (aquí sí rigen las variables TLS del inventario):
```bash
cd anomalia-infra
ansible-playbook -i inventory.ini deploy-infra.yml
```

### 3. Destrucción Limpia del Stack (`destroy-infra.yml`)
```bash
cd anomalia-infra
ansible-playbook -i inventory.ini destroy-infra.yml
```
> [!NOTE]
> El playbook de destrucción detecta automáticamente el motor de contenedores y elimina contenedores, redes (`anomalia_aiops-net`), volúmenes y unidades systemd de Victoria y del firewall, manteniendo intactas las imágenes base cacheadas (`postgres`, `ollama`) y los certificados TLS en `/opt/anomalia/certs`. Además, retira las unidades **derivadas** `anomalia-vmalert-*.service` (vmalert por-tenant) descubiertas por `find`, sin hardcodear slugs. Es una operación **explícita de limpieza**, no un requisito previo para redeployar.

### 4. Topología Flexible (inventario = única fuente)
La topología se decide **libremente en `inventory.ini`**: quien instala coloca las IPs en cada grupo (`vlogs_*_nodes`, `vm_*_nodes`, `vt_*_nodes`, `pyroscope_nodes`, `vmauth_nodes`, `vmagent_nodes`, `alertmanager_nodes`, `vmalert_nodes`, `backend_nodes`, `parses_nodes`) y un **mismo host puede pertenecer a cualquier combinación de grupos**. Cada unit systemd se despliega únicamente en los hosts de su grupo (no se asume un layout monolítico). Las referencias cruzadas entre componentes usan `hostvars[groups['X'][0]]` prefiriendo la IP de servicio (`*_ip`) con fallback a `ansible_host` y `127.0.0.1`. Detalle completo en `specs/013-deployment-topology-and-idempotency.md`.

Usá `inventory.ini.local.example` para un host local y `inventory.ini.multi.example`
para servidores distintos. En multi, backend y Parses pueden estar en hosts separados:
se comunican por `backend_ip:backend_port` y `parses_ip:parses_port`. Si comparten
host, se usa el DNS del bridge (`anomalia_gw`, `parses`). La red Docker se crea en
cada host con motor; el firewall permite las IPs de todos los nodos del inventario.

---

## 🔄 Mecanismos Avanzados de Sincronización

- **Regeneración Incremental de Scrapes (`sync-scrapes.yml`):** Al desplegar o dar de baja una instancia vmalert por tenant, se encola automáticamente un proceso que regenera la configuración completa de `vmagent` y `vmauth` en los nodos correspondientes sin necesidad de reinstalar los binarios base.
- **Sincronización de Reglas (`sync-vmalert-rules.yml`):** Permite materializar las reglas YAML almacenadas en la base de datos hacia las rutas dedicadas en cada nodo (`/etc/anomalia/vmalert/<tenant_slug>/alert_rules.yml`) aplicando recarga en caliente (`/-/reload`).

### 5. Orden de Roles y Provisioning de Parses
- El rol `parses` corre **antes** que el rol `backend` y espera readiness del puerto (`wait_for`): el gateway reprovisiona el proyecto de Parses al arrancar, por lo que Perses debe estar listo primero.
- Tras un destroy+deploy los datos de Parses se pierden (`/perses` sin volumen) y el backend ejecuta un **catch-up no bloqueante al arranque** que recrea project + datasources + dashboards para todos los usuarios activos (idempotente, con reintentos). Detalle en `specs/008-parses-datasources-and-tenant-scoping.md`.

### 6. Aislamiento L4 de puertos de lectura (`victoria_firewall`)
El rol `victoria_firewall` restringe el acceso a los puertos de **lectura** de la
telemetría (nunca expuestos públicamente):

| Puerto | Servicio |
|---|---|
| `8401` | vmselect (VictoriaMetrics) |
| `8481` | vlselect (VictoriaLogs) |
| `8491` | vtselect (VictoriaTraces) |
| `4040` | Pyroscope |

El aislamiento admite **subred del puente de contenedores, loopback, la IP del
host y las IPs de todos los nodos del inventario**, y se implementa con **rich rules** de `firewalld` (RHEL) o una
cadena `iptables` `ANOMALIA_VICTORIA_READ` (Debian/Ubuntu), auto-detectando el
backend. No requiere colecciones Ansible. Palancas:

- `victoria_firewall_enabled` (default `true`) — desactivar si el security group del cloud ya aísla.
- `victoria_firewall_allowed_sources` — CIDRs/fuentes adicionales permitidas (acotar a la subred del puente y CIDRs de administración/VPN).

El `destroy-infra.yml` retira el aislamiento (unidad `anomalia-victoria-firewall`,
la cadena iptables con su salto en `INPUT` y las rich rules). Detalle en
`specs/009-platform-support-and-prerequisites.md`.

### 7. Token webhook AM ↔ Backend

El receiver de Alertmanager y el backend comparten un token Bearer para el
webhook de alertas. `alertmanager_webhook_token` se resuelve en `deploy-infra.yml`
con esta precedencia:

1. `lookup('env', 'ALERTMANAGER_WEBHOOK_TOKEN')`, si la variable de entorno no
   está vacía (compatible con el workflow self-hosted, que la inyecta desde un
   secreto de GitHub).
2. `lookup('password', '<playbook_dir>/.secrets/alertmanager_webhook_token')`:
   reutiliza el archivo local si existe o lo genera la primera vez (64
   caracteres alfanuméricos).

El archivo local vive en `.secrets/`, está ignorado por git y por el allowlist
de gitleaks (por path), y queda con permisos `0700` en el directorio y `0600` en
el archivo. La primera `pre_task` de `deploy-infra.yml` crea el directorio en el
nodo de control para que el lookup no falle en el primer deploy.

- **Rotar el token:** borrar `.secrets/alertmanager_webhook_token` y redeployar.
  Gateway y Alertmanager reciben el nuevo valor en la misma corrida.
- **Override:** una var de inventario o `-e alertmanager_webhook_token=...`
  tiene mayor precedencia.
- **Desactivar auth explícitamente:** `-e alertmanager_webhook_token=""`. El
  endpoint y el receiver operan sin autenticación (solo para instalaciones
  internas de desarrollo).

> En el runner self-hosted, el step de checkout usa `clean: false` para
> conservar `inventory.ini` y `.secrets/` entre corridas. También se puede
> definir el secret `INVENTORY_INI` para materializar el inventario.

### 8. Certificados TLS y gateway Nginx

El gateway TLS es un contenedor **Nginx** (`anomalia_gw_tls`) que reemplaza al
antiguo FastAPI TLS:

- `80`: redirige `301` a HTTPS cuando hay certificado externo; en `disabled` proxya en claro.
- `443`: termina TLS con el certificado externo (generado o provisto).
- `8443`: listener TLS interno (solo red de contenedores) para Parses.
- El backend FastAPI/Uvicorn (`anomalia_gw`) queda en `8000` y **no termina TLS**;
  Nginx le reenvía las peticiones en claro. `/healthz` y `/metrics` se consultan en
  `http://<IP>:8000`. vmagent expone sus métricas en `http://<IP>:8429/metrics`.

El material vive en `/opt/anomalia/certs` y `destroy-infra.yml` lo preserva:

| Ruta | Contenido |
|---|---|
| `external/ca.crt` | CA privada que firma el leaf externo generado; hay que confiarla manualmente en clientes |
| `external/fullchain.pem` + `external/privkey.pem` | Certificado público (leaf + CA en el modo generado) |
| `internal/fullchain.pem` + `internal/privkey.pem` | TLS interno de Parses |
| `internal/ca.crt` | CA que valida Parses |

El modo generado **no** es un leaf autofirmado suelto: Ansible crea una CA local
(`Anomalia Root CA`) y firma con ella el leaf cuyo CN es `certs_hostname` —por default
`backend_ip`, o la IP detectada si no está definida— y cuyo SAN cubre esa IP, la IP
detectada, `anomalia.local`, `localhost` y `127.0.0.1`. El deploy no instala esa CA en
navegadores ni en el celular; cada cliente debe confiarla por su cuenta.

#### Modo generado (`self_signed`, default)

```bash
./scripts/deploy.sh
./scripts/deploy.sh --hostname anomalia.mi-dominio.local
```

Ansible genera la CA y el leaf con CN = IP del backend (o `--hostname`) y SAN con
esa IP, la IP detectada, `anomalia.local`, `localhost` y `127.0.0.1`. El navegador advierte hasta que
se confíe en `external/ca.crt`; para probar en el celular abrí el admin con la IP de
la LAN: el QR usa el origen actual del panel y sale con esa IP.

Cambiar el SAN o rotar la CA de un certificado ya generado requiere `--tls-force`:

```bash
./scripts/deploy.sh --hostname anomalia.mi-dominio.local --tls-force
```

#### Modo provisto

```bash
./scripts/deploy.sh --cert /ruta/fullchain.pem --key /ruta/privkey.pem
```

También se puede fijar en el inventario **si se invoca el playbook directamente**:

```ini
certs_mode="provided"
certs_hostname="anomalia.mi-dominio.com"
certs_external_cert="/ruta/fullchain.pem"
certs_external_key="/ruta/privkey.pem"
```

Recordatorio: `deploy.sh` sobrescribe `certs_mode` (y, cuando se pasan las opciones,
también `certs_hostname`, `certs_external_cert` y `certs_external_key`) con `-e`, así
que esas variables del inventario no rigen en el wrapper.

O dejar los archivos en `.secrets/certs/fullchain.pem` y
`.secrets/certs/privkey.pem`; `deploy.sh` los detecta y usa `provided`
automáticamente. `.secrets/` está ignorado por git y por gitleaks.

Requisitos del material provisto:

- `fullchain.pem` debe incluir el certificado del servidor y los intermedios.
- `privkey.pem` debe ser la clave correspondiente, **sin passphrase** (Nginx no
  puede desbloquearla sin intervención).
- El SAN ya cubre la IP detectada y `anomalia.local`; si usás otro dominio, pasalo
  con `--hostname <dominio>` o `certs_hostname` y regenerá con `--tls-force`.
- Ansible valida clave/certificado, vencimiento y SAN antes de recargar Nginx.
  Un error aborta la recarga y deja el Nginx anterior sirviendo el cert viejo.
- Si ya existe `external/fullchain.pem` sin el marcador `.managed-by-ansible`
  (por ejemplo, un cert provisto colocado a mano), Ansible lo conserva aunque
  `certs_mode` sea `self_signed`. Para reemplazarlo por un autofirmado nuevo,
  usá `--tls-force`.

Para más SANs en modo autofirmado, sobreescribí `certs_extra_dns` y `certs_ips`
(por ejemplo con `-e '{"certs_extra_dns":["anomalia.local","otro.local"]}'`).

#### Renovación sin redeploy

```bash
./scripts/deploy.sh --tls-only --cert /ruta/fullchain.pem --key /ruta/privkey.pem
./scripts/deploy.sh --tls-only --tls-force   # rotar autofirmado
```

`--tls-only` ejecuta `deploy-tls.yml`: copia/valida certificados, corre
`nginx -t`, recarga Nginx y reinicia `anomalia_gw` para refrescar la CA interna
cacheada por el provisioner de Parses. **No** ejecuta `docker compose down -v`,
así que no pierde base ni volúmenes.

> `--tls-only` asume que ya corrés el gateway Nginx. Si venís de una instalación
> anterior con el FastAPI TLS, hacé un deploy completo una vez para migrar el
> contenedor. Los cambios de `certs_mode` (por ejemplo `disabled` ↔
> `self_signed`) también requieren deploy completo porque cambian los puertos
> publicados por Compose.

#### Desactivar TLS externo

```bash
./scripts/deploy.sh --tls-mode disabled
```

Nginx publica solo `:80` en claro; el TLS interno `:8443` sigue existiendo para
Parses. No se recomienda en instalaciones expuestas.

#### Equivalente manual

```bash
ansible-playbook -i inventory.ini deploy-infra.yml \
  -e certs_mode=provided \
  -e certs_hostname=anomalia.mi-dominio.com \
  -e certs_external_cert=/ruta/fullchain.pem \
  -e certs_external_key=/ruta/privkey.pem

ansible-playbook -i inventory.ini deploy-tls.yml -e certs_mode=provided \
  -e certs_external_cert=/ruta/fullchain.pem -e certs_external_key=/ruta/privkey.pem
```
