# anomalia-infra

Infraestructura como código (IaC) de **Anomalia**: despliegue, actualización y destrucción del
stack de observabilidad con **Ansible**.

## Stack

- **Ansible** (solo módulos `ansible.builtin`; sin colecciones externas)
- Ecosistema **Victoria**: VictoriaMetrics, VictoriaLogs, VictoriaTraces, vmagent, vmauth, vmalert, Alertmanager
- **Parses** (Perses) y **Pyroscope**
- Contenedores: **Docker CE** o **Podman rootful** (Compose v1/v2 o `podman-compose`)

## Estructura

```
roles/            # backend, certs, parses, vmauth, vmalert, victoria_*, victoria_firewall, ...
tasks/            # detect_container_stack.yml
deploy-infra.yml  # despliegue completo
destroy-infra.yml # destrucción limpia
install-binaries.yml
sync-scrapes.yml
sync-vmalert-rules.yml
inventory.ini     # topología = única fuente
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

> El role `backend` copia el source de [`anomalia-backend`](../anomalia-backend) desde un
> directorio hermano (`../anomalia-backend` por defecto; sobreescribible con
> `-e anomalia_backend_src=/ruta`).

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
