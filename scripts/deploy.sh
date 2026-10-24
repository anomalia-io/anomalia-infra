#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

INVENTORY="${ANOMALIA_INVENTORY:-}"
BACKEND_SRC="${ANOMALIA_BACKEND_SRC:-}"
BACKEND_REF="${ANOMALIA_BACKEND_REF:-main}"
BACKEND_REPO="${ANOMALIA_BACKEND_REPO:-git@github.com:anomalia-io/anomalia-backend.git}"
ASSUME_YES=0
TMP_DIR=""

usage() {
  cat <<'EOF'
Deploy de Anomalia (infra + backend).

Uso:
  ./scripts/deploy.sh [opciones]

Opciones:
  -i, --inventory PATH   Inventario de Ansible (default: inventory.ini del repo)
  -b, --backend-src PATH Checkout local del backend (default: clonar por SSH)
  -r, --backend-ref REF  Rama/tag del backend a clonar (default: main)
  -y, --yes              No pedir confirmación ante un redeploy destructivo
  -h, --help             Mostrar esta ayuda
EOF
}

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'ADVERTENCIA: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT
trap 'printf "ERROR: falló en línea %s\n" "${BASH_LINENO[0]:-?}" >&2' ERR

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--inventory) [[ $# -ge 2 ]] || die "Falta el valor de $1"; INVENTORY="$2"; shift 2;;
      --inventory=*) INVENTORY="${1#*=}"; shift;;
      -b|--backend-src) [[ $# -ge 2 ]] || die "Falta el valor de $1"; BACKEND_SRC="$2"; shift 2;;
      --backend-src=*) BACKEND_SRC="${1#*=}"; shift;;
      -r|--backend-ref) [[ $# -ge 2 ]] || die "Falta el valor de $1"; BACKEND_REF="$2"; shift 2;;
      --backend-ref=*) BACKEND_REF="${1#*=}"; shift;;
      -y|--yes) ASSUME_YES=1; shift;;
      -h|--help) usage; exit 0;;
      *) die "Opción desconocida: $1";;
    esac
  done
}

validate_inventory() {
  local inv="$1"
  [[ -f "$inv" ]] || return 1
  # Corrupción típica: el archivo empieza con la salida de un comando.
  head -1 "$inv" | grep -qE '^[[:space:]]*(cat|echo|printf) ' && return 2
  [[ -s "$inv" ]] || return 2
  grep -qE '^[[:space:]]*\[[^]]+\]' "$inv" || return 2
  return 0
}

find_valid_runner_inventory() {
  local candidate
  for candidate in \
    "${HOME}"/actions-runner/_work/anomalia-infra/*/inventory.ini \
    "${HOME}"/actions-runner/_work/*/*/inventory.ini; do
    [[ -f "$candidate" ]] || continue
    if validate_inventory "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    warn "Ignorando inventario inválido/corrupto: $candidate"
  done
  return 1
}

resolve_inventory() {
  local source="" rc=0
  if [[ -n "$INVENTORY" ]]; then
    [[ -f "$INVENTORY" ]] || die "No existe: $INVENTORY"
    validate_inventory "$INVENTORY" || { rc=$?; [[ $rc -eq 2 ]] && die "Inventario corrupto: $INVENTORY"; }
    return
  fi
  INVENTORY="${REPO_ROOT}/inventory.ini"
  if [[ -f "$INVENTORY" ]]; then
    if validate_inventory "$INVENTORY"; then
      :
    elif [[ $? -eq 2 ]]; then
      warn "Inventario corrupto, buscando uno válido..."
      rm -f "$INVENTORY"
    fi
  fi
  if [[ -f "$INVENTORY" ]]; then
    validate_inventory "$INVENTORY" && return
  fi
  if [[ -n "${ANOMALIA_INVENTORY_SRC:-}" && -f "${ANOMALIA_INVENTORY_SRC}" ]]; then
    validate_inventory "${ANOMALIA_INVENTORY_SRC}" && source="${ANOMALIA_INVENTORY_SRC}" || die "ANOMALIA_INVENTORY_SRC inválido/corrupto"
  fi
  if [[ -z "$source" ]]; then
    source="$(find_runner_inventory || true)"
  fi
  if [[ -z "$source" ]]; then
    for candidate in "${HOME}"/actions-runner/_work/*/*/inventory.ini; do
      [[ -f "$candidate" ]] || continue
      if validate_inventory "$candidate"; then source="$candidate"; break; fi
    done
  fi
  [[ -n "$source" ]] || die "No hay inventory.ini válido. Copiá inventory.ini.example y editálo o usá --inventory."
  log "Copiando inventario desde: $source"
  install -m 600 "$source" "$INVENTORY"
}

check_inventory_placeholders() {
  grep -qw 'HOST' "$INVENTORY" && die "El inventario contiene placeholder 'HOST': $INVENTORY"
}

preflight() {
  command -v ansible-playbook >/dev/null 2>&1 || die "Falta ansible-playbook"
  command -v git >/dev/null 2>&1 || die "Falta git"
  [[ -f "${REPO_ROOT}/deploy-infra.yml" ]] || die "Falta deploy-infra.yml"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"${TMPDIR:-/tmp}/anomalia-deploy-$(id -u).lock"
    flock -n 9 || die "Ya hay un deploy en curso"
  fi
}

confirm_if_destructive() {
  [[ -f /opt/anomalia/backend/docker-compose.yml ]] || return 0
  warn "Ya hay despliegue en /opt/anomalia/backend. Se hará docker compose down -v."
  (( ASSUME_YES )) && return 0
  local ans=""
  read -r -p "Escribí 'deploy' para continuar: " ans </dev/tty || die "Cancelado"
  [[ "$ans" == "deploy" ]] || die "Cancelado"
}

prepare_backend() {
  if [[ -n "$BACKEND_SRC" ]]; then
    [[ -d "$BACKEND_SRC" ]] || die "No existe backend: $BACKEND_SRC"
    BACKEND_SRC="$(cd -- "$BACKEND_SRC" && pwd)"
    log "Usando checkout local: $BACKEND_SRC"
    return
  fi
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/anomalia-deploy.XXXXXX")"
  BACKEND_SRC="${TMP_DIR}/anomalia-backend"
  log "Clonando backend: $BACKEND_REPO (ref=$BACKEND_REF)"
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" git clone --depth 1 --branch "$BACKEND_REF" "$BACKEND_REPO" "$BACKEND_SRC"
}

announce_token_source() {
  if [[ -n "${ALERTMANAGER_WEBHOOK_TOKEN:-}" ]]; then
    log "Token webhook: usando ALERTMANAGER_WEBHOOK_TOKEN"
  else
    log "Token webhook: usando/generando .secrets/alertmanager_webhook_token"
  fi
}

deploy() {
  log "Verificando sintaxis"
  (cd "$REPO_ROOT" && ansible-playbook -i "$INVENTORY" deploy-infra.yml --syntax-check)
  log "Desplegando"
  (cd "$REPO_ROOT" && ansible-playbook -i "$INVENTORY" deploy-infra.yml -e "anomalia_backend_src=$BACKEND_SRC")
}

show_status() {
  log "Estado"
  command -v docker >/dev/null && docker ps --format 'table {{.Names}}\t{{.Status}}' || true
  systemctl list-units 'anomalia-*' --all --no-pager 2>/dev/null || true
  if grep -q 'ansible_connection=local' "$INVENTORY" 2>/dev/null; then
    for u in "http://127.0.0.1:8000/healthz" "http://127.0.0.1:8427/health" "http://127.0.0.1:8090/"; do
      curl -fsS --max-time 3 "$u" >/dev/null 2>&1 && echo "OK    $u" || echo "AVISO $u sin respuesta"
    done
  fi
}

main() {
  parse_args "$@"
  preflight
  resolve_inventory
  check_inventory_placeholders
  announce_token_source
  confirm_if_destructive
  prepare_backend
  deploy
  show_status
  log "Deploy completado"
}

main "$@"
