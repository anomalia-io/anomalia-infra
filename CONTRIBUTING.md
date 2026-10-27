# CONTRIBUTING.md - Anomalia Infra

## 👨‍💻 Flujo de Desarrollo (SSD + Ansible)

Los cambios en playbooks, roles, tasks o variables de inventario deben seguir el protocolo **Specs-Anchored Development (SSD)** y las invariantes de `specs/013`.

### ⚠️ Antes de Modificar

1. **Syntax Check** (siempre, antes de commitear o modificar):
   ```bash
   ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check
   ansible-playbook -i inventory.ini destroy-infra.yml --syntax-check
   ```

2. **Validar invariantes SSD** (`specs/013 §2-4`):
   - Groups siempre con `groups.get('X', [])` - **NUNCA** `groups['X']`
   - Cada unit condicionada a su grupo: `when: inventory_hostname in groups.get('<grupo>', [])`
   - Idempotencia: `state=present`/`state=started`/`state=enabled` son la norma
   - Cross-refs: `hostvars[groups['X'][0]]` con fallback `*_ip | default(ansible_host) | default('127.0.0.1')`
   - `StartLimitIntervalSec=0` y `After=network-online.target` en templates `.service.j2`

3. **Topología flexible**:
   - Un host puede pertenecer a múltiples grupos
   - `inventory.ini` es la **única fuente de verdad**
   - No asumir layout monolítico "todos en un solo host"

4. **Revisar riesgos aceptados** (spec 006):
   - `change-me-secret`, `anomal_password`, `admin_password` = riesgo aceptado
   - No intentar added reglas de gitleaks para estos valores

5. **Verificar topología** con `inventory_hostname in groups.get('<grupo>', [])` en cada task

### 📝 Después de Modificar

1. **Hacer syntax check** (SIEMPRE):
   ```bash
   ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check
   ansible-playbook -i inventory.ini destroy-infra.yml --syntax-check
   ```

2. **Probar en entorno controlado** (opcional pero recomendado):
   ```bash
   ansible-playbook -i inventory.ini deploy-infra.yml --check
   ```

3. **Commit con firma SSH**:
   ```bash
   git add .
   git commit -S -m "infra: <descripción del cambio>"
   git push origin main
   ```
   - **Obligatorio** el flag `-S` para firma SSH verificada
   - `user.signingkey = ~/.ssh/id_ed25519_personal.pub`
   - `user.email = jo.asd.xd@gmail.com`

4. **Opcional: Invocar `@spec-sync`** desde la sesión `anomalia-infra`:
   - El subagente propone update en `anomalia-meta/specs/`
   - El usuario approvar y commit en `anomalia-meta`

### ⚠️ Consideraciones Adicionales

- `ANOMALIA_RUN_WORKERS=false` fijo en contenedor TLS (`docker-compose.yml.j2`)
- `WorkerSupervisor` con `pg_try_advisory_lock(0x414E4F53)` - único executor único por BD
- Heartbeat cada 15s, `_recover_orphans` si heartbeat_at stale
- `deploy-infra.yml` incluye post-task idempotente que re-sincroniza `admin_password`
- Roles `victoria_firewall` detecta automáticamente iptables vs firewalld
- `victoria_firewall_allowed_sources` = acotar a subred exacta del puente en producción

### 📦 Stack

- **Ansible** (solo módulos `ansible.builtin`; sin colecciones externas)
- Ecosistema **Victoria**: VictoriaMetrics, VictoriaLogs, VictoriaTraces, vmagent, vmauth, vmalert, Alertmanager
- **Parses** (Perses) y **Pyroscope**
- Contenedores: **Docker CE** o **Podman rootful** (Compose v1/v2 o `podman-compose`)

### 📋 Checklist Pre-Commit

| Item | Verificar |
|------|-----------|
| Syntax check deploy-infra.yml pasa | ✅ |
| Syntax check destroy-infra.yml pasa | ✅ |
| Invariantes SSD (groups.get, idempotencia) | ✅ |
| Topología flexible verificada | ✅ |
| Sin hardcodeo de credenciales | ✅ |
| Commit con firma SSH (`-S`) | ✅ |
| `victoria_firewall` respete `allowed_sources` | ✅ |

### 📦 Piles

```bash
# Syntax check (siempre antes de modificar)
ansible-playbook -i inventory.ini deploy-infra.yml --syntax-check
ansible-playbook -i inventory.ini destroy-infra.yml --syntax-check

# Probar en entorno controlado
ansible-playbook -i inventory.ini deploy-infra.yml --check

# Commiteo
git add .
git commit -S -m "infra: <descripción>"
git push origin main
```

## 📄 Licencia

[Apache-2.0](./LICENSE)