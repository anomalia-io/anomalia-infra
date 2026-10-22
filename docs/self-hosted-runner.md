# Runner self-hosted para deploy automatizado

El workflow `anomalia-infra/.github/workflows/deploy.yml` corre en un runner
**self-hosted** instalado en la máquina destino (por defecto `192.168.1.27`).
Al publicarse un release en `anomalia-infra` (o al dispararse manualmente)
ejecuta `ansible-playbook -i inventory.ini deploy-infra.yml`, clonando
`anomalia-backend` dentro del workspace vía **SSH** (por eso la clave del
usuario del runner necesita acceso de lectura a los repos de la org).

## Prerrequisitos en la máquina destino

1. **Ansible** instalado y accesible por el usuario que corre el runner.
2. **sudo sin password** para ese usuario (el deploy usa `become: yes`):
   ```
   echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/actions-runner
   sudo chmod 440 /etc/sudoers.d/actions-runner
   ```
3. **Docker o Podman** operativo (igual que para un deploy manual).
4. El usuario del runner debe poder clonar los repos privados de la org.

## Obtener el token de registro

El token de registro se genera por web (requiere ser owner/admin de la org):

```
https://github.com/organizations/anomalia-io/settings/actions/runners/new
```

Elegí **Linux / x64** y copiá el bloque `./config.sh --url ... --token <TOKEN>`.

> Alternativa por API (requiere scope `admin:org`):
> `gh auth refresh -h github.com -s admin:org`
> `gh api -X POST orgs/anomalia-io/actions/runners/registration-token -q .token`

## Instalación (script)

```bash
TOKEN=<token-de-registro> scripts/install-self-hosted-runner.sh
```

Opcionalmente fijar versión y etiquetas:

```bash
RUNNER_VERSION=2.331.0 RUNNER_LABELS="self-hosted,linux,x64,anomalia-deploy" \
  TOKEN=<token> scripts/install-self-hosted-runner.sh
```

El script:

- descarga el runner oficial (verificando `sha256` del manifest),
- lo registra como servicio `systemd` (`svc.sh install` + `start`),
- usa etiquetas por defecto `self-hosted,linux,x64,anomalia-deploy`.

> El runner clona `anomalia-backend` por SSH, así que la clave del usuario
> debe tener acceso de lectura a `anomalia-io/anomalia-backend` y el host
> `github.com` presente en `~/.ssh/known_hosts` (el deploy usa
> `StrictHostKeyChecking=accept-new`).

No requiere `sudo` para instalar el runner en sí (se instala en
`~/actions-runner`), pero **sí** para registrar el servicio y para el
`sudoers` del deploy.

## Verificación

```bash
gh api orgs/anomalia-io/actions/runners -q '.runners[] | "\(.name) \(.status) \(.busy)"'
```

Debe aparecer `online`. Luego, desde `anomalia-infra`:

```bash
gh workflow run deploy.yml --repo anomalia-io/anomalia-infra
gh run watch --repo anomalia-io/anomalia-infra
```

## Seguridad

- El runner se registra a nivel **organización**; cualquier repo de la org
  con workflows puede usarlo. Si se quiere acotar, registrar a nivel repo
  (`--url https://github.com/anomalia-io/anomalia-infra`) en lugar de org.
- El token de registro es efímero (expira en ~1h) y de un solo uso.
- Revisar que ningún workflow de PR no confiable corra en el runner
  self-hosted: `deploy.yml` sólo se dispara por `release: published` o
  `workflow_dispatch` (nunca por PRs de forks).
