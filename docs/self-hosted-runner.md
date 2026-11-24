# Runner self-hosted para deploy automatizado

El workflow `anomalia-infra/.github/workflows/deploy-selfhosted.yml` corre en un
runner **self-hosted** instalado en la máquina destino (por defecto
`192.168.1.27`). Al publicarse un release en `anomalia-infra` (o al dispararse
manualmente) ejecuta `scripts/deploy.sh`, que clona `anomalia-backend` dentro
del workspace vía **SSH** (por eso la clave del usuario del runner necesita
acceso de lectura a los repos de la org) y aplica `deploy-infra.yml`.

## Prerrequisitos en la máquina destino

1. **Ansible** instalado y accesible por el usuario que corre el runner.
2. **sudo sin password** para ese usuario (el deploy usa `become: yes`):
   ```
   echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/actions-runner
   sudo chmod 440 /etc/sudoers.d/actions-runner
   ```
3. **Docker o Podman** operativo (igual que para un deploy manual).
4. El usuario del runner debe poder clonar los repos privados de la org.
5. **Inventario persistente**: el workflow usa `actions/checkout` con
   `clean: false`, así que conserva `inventory.ini` y `.secrets/` (ignorados por
   git) entre corridas. Dejá el inventario en el workspace del runner o definí el
   secret `INVENTORY_INI`; si no existe ninguno, `scripts/deploy.sh` falla con
   instrucciones.

## Obtener el token de registro

El token de registro se genera por web (requiere ser owner/admin de la org):

```
https://github.com/organizations/anomalia-io/settings/actions/runners/new
```

Elegí **Linux / x64** y copiá el bloque `./config.sh --url ... --token <TOKEN>`.

> Alternativa por API (requiere scope `admin:org`):
> `gh auth refresh -h github.com -s admin:org`
> `gh api -X POST orgs/anomalia-io/actions/runners/registration-token -q .token`

## Instalación manual

No hay un script `scripts/install-self-hosted-runner.sh` en este repo. Seguí las
instrucciones oficiales que muestra GitHub al generar el token de registro:

1. Descargá el paquete del runner para **Linux / x64** y descomprimilo en
   `~/actions-runner` (o el directorio que prefieras).
2. Registralo con el comando `./config.sh --url ... --token <TOKEN>` que copiaste
   de la web. Las etiquetas por defecto son `self-hosted`, `linux` y `x64`, que
   alcanzan para el `runs-on: self-hosted` del workflow.
3. Instalá y arrancá el servicio con `sudo ./svc.sh install` y `./svc.sh start`.

> El runner clona `anomalia-backend` por SSH (rama `main`), así que la clave del
> usuario debe tener acceso de lectura a `anomalia-io/anomalia-backend` y el host
> `github.com` presente en `~/.ssh/known_hosts` (el deploy usa
> `StrictHostKeyChecking=accept-new`).

No requiere `sudo` para descomprimir y configurar el runner en sí, pero **sí** para
instalar el servicio systemd y para el `sudoers` del deploy.

## Inventario y token en el workspace

El deploy preserva dos archivos locales del workspace del runner:

- `inventory.ini`: topología real de los nodos. Partí de `inventory.ini.local.example` (prueba local) o `inventory.ini.multi.example` (implementación real). Opciones:
  - dejarlo en `~/actions-runner/_work/anomalia-infra/anomalia-infra/inventory.ini`;
  - definirlo como secret `INVENTORY_INI` (el workflow lo materializa en cada
    corrida);
  - `scripts/deploy.sh` también lo copia desde `ANOMALIA_INVENTORY_SRC` o desde
    otro checkout del workspace si falta.
- `.secrets/alertmanager_webhook_token`: token compartido AM ↔ Backend. Si no
  se define `ALERTMANAGER_WEBHOOK_TOKEN`, el playbook lo genera la primera vez y
  lo reutiliza en corridas posteriores. Para rotarlo, borrá el archivo y
  redeployá.

Con `clean: false`, el checkout no borra archivos ignorados; si necesitás forzar
un workspace limpio, eliminá manualmente `inventory.ini` y `.secrets/` (el token
se regenerará).

## Verificación

```bash
gh api orgs/anomalia-io/actions/runners -q '.runners[] | "\(.name) \(.status) \(.busy)"'
```

Debe aparecer `online`. Luego, desde `anomalia-infra`:

```bash
gh workflow run deploy-selfhosted.yml --repo anomalia-io/anomalia-infra
gh run watch --repo anomalia-io/anomalia-infra
```

## Seguridad

- El runner se registra a nivel **organización**; cualquier repo de la org
  con workflows puede usarlo. Si se quiere acotar, registrar a nivel repo
  (`--url https://github.com/anomalia-io/anomalia-infra`) en lugar de org.
- El token de registro es efímero (expira en ~1h) y de un solo uso.
- Revisar que ningún workflow de PR no confiable corra en el runner
  self-hosted: `deploy-selfhosted.yml` sólo se dispara por `release: published` o
  `workflow_dispatch` (nunca por PRs de forks).
