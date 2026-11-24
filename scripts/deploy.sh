#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

INVENTORY="${ANOMALIA_INVENTORY:-}"
BACKEND_SRC="${ANOMALIA_BACKEND_SRC:-}"
BACKEND_REF="${ANOMALIA_BACKEND_REF:-main}"
BACKEND_REPO="${ANOMALIA_BACKEND_REPO:-git@github.com:anomalia-io/anomalia-backend.git}"
TLS_MODE="${ANOMALIA_TLS_MODE:-}"
TLS_HOSTNAME="${ANOMALIA_TLS_HOSTNAME:-}"
TLS_CERT="${ANOMALIA_TLS_CERT:-}"
TLS_KEY="${ANOMALIA_TLS_KEY:-}"
TLS_FORCE="${ANOMALIA_TLS_FORCE:-0}"
TLS_ONLY=0
EXTRA_VARS=()
ASSUME_YES=0
RESET_DATA=0
TMP_DIR=""
BACKEND_SOURCE_EXCLUDES=(
  --exclude='./.git'
  --exclude='./.opencode'
  --exclude='./.pytest_cache'
  --exclude='./.mypy_cache'
  --exclude='./.ruff_cache'
  --exclude='./.venv'
  --exclude='./venv'
  --exclude='__pycache__'
  --exclude='*/__pycache__'
  --exclude='node_modules'
  --exclude='*/node_modules'
  --exclude='*.pyc'
  --exclude='*.pyo'
)

usage() {
  cat <<'EOF'
Deploy de Anomalia (infra + backend).

Uso:
  ./scripts/deploy.sh [opciones]

Opciones:
  -i, --inventory PATH   Inventario de Ansible (default: inventory.ini del repo)
                         Plantillas: inventory.ini.local.example (prueba local) e
                         inventory.ini.multi.example (implementación real)
  -b, --backend-src PATH Checkout local del backend (default: clonar por SSH)
  -r, --backend-ref REF  Rama/tag del backend a clonar (default: main)
  --tls-mode MODE        self_signed | provided | disabled (default: self_signed)
  --hostname NAME        CN/SAN del certificado externo (default: IP detectada)
  --cert PATH            fullchain.pem provisto (implica --tls-mode provided)
  --key PATH             privkey.pem provisto (implica --tls-mode provided)
  --tls-force            Regenera certificados autofirmados (no borra provistos)
  --tls-only             Renueva certificados y recarga Nginx sin redeploy
  --reset-data           Borra volúmenes de PostgreSQL/Ollama (pide confirmación)
  -y, --yes              No pedir confirmación con --reset-data
  -h, --help             Mostrar esta ayuda

Si existen .secrets/certs/fullchain.pem y .secrets/certs/privkey.pem, se usan
automáticamente como certificado provisto.
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
      --tls-mode) [[ $# -ge 2 ]] || die "Falta el valor de $1"; TLS_MODE="$2"; shift 2;;
      --tls-mode=*) TLS_MODE="${1#*=}"; shift;;
      --hostname) [[ $# -ge 2 ]] || die "Falta el valor de $1"; TLS_HOSTNAME="$2"; shift 2;;
      --hostname=*) TLS_HOSTNAME="${1#*=}"; shift;;
      --cert) [[ $# -ge 2 ]] || die "Falta el valor de $1"; TLS_CERT="$2"; shift 2;;
      --cert=*) TLS_CERT="${1#*=}"; shift;;
      --key) [[ $# -ge 2 ]] || die "Falta el valor de $1"; TLS_KEY="$2"; shift 2;;
      --key=*) TLS_KEY="${1#*=}"; shift;;
      --tls-force) TLS_FORCE=1; shift;;
      --tls-only) TLS_ONLY=1; shift;;
      --reset-data) RESET_DATA=1; shift;;
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
      die "Inventario corrupto: $INVENTORY. Corregilo o elegí otro con --inventory; no se eliminó."
    fi
  fi
  if [[ -f "$INVENTORY" ]]; then
    validate_inventory "$INVENTORY" && return
  fi
  if [[ -n "${ANOMALIA_INVENTORY_SRC:-}" && -f "${ANOMALIA_INVENTORY_SRC}" ]]; then
    validate_inventory "${ANOMALIA_INVENTORY_SRC}" && source="${ANOMALIA_INVENTORY_SRC}" || die "ANOMALIA_INVENTORY_SRC inválido/corrupto"
  fi
  if [[ -z "$source" ]]; then
    source="$(find_valid_runner_inventory || true)"
  fi
  if [[ -z "$source" ]]; then
    for candidate in "${HOME}"/actions-runner/_work/*/*/inventory.ini; do
      [[ -f "$candidate" ]] || continue
      if validate_inventory "$candidate"; then source="$candidate"; break; fi
    done
  fi
  [[ -n "$source" ]] || die "No hay inventory.ini válido. Copiá inventory.ini.local.example o inventory.ini.multi.example y editálo, o usá --inventory."
  log "Copiando inventario desde: $source"
  install -m 600 "$source" "$INVENTORY"
}

check_inventory_placeholders() {
  if grep -qw 'HOST' "$INVENTORY"; then
    die "El inventario todavía contiene el placeholder 'HOST': $INVENTORY
Editá el archivo con las IPs reales antes de desplegar."
  fi
}

preflight() {
  command -v ansible-playbook >/dev/null 2>&1 || die "Falta ansible-playbook"
  command -v git >/dev/null 2>&1 || die "Falta git"
  command -v tar >/dev/null 2>&1 || die "Falta tar"
  if (( TLS_ONLY )); then
    [[ -f "${REPO_ROOT}/deploy-tls.yml" ]] || die "Falta deploy-tls.yml"
  else
    [[ -f "${REPO_ROOT}/deploy-infra.yml" ]] || die "Falta deploy-infra.yml"
  fi
  if command -v flock >/dev/null 2>&1; then
    exec 9>"${TMPDIR:-/tmp}/anomalia-deploy-$(id -u).lock"
    flock -n 9 || die "Ya hay un deploy en curso"
  fi
}

resolve_tls() {
  local secrets_dir="${REPO_ROOT}/.secrets/certs"
  if [[ -z "$TLS_CERT" && -z "$TLS_KEY" && -f "${secrets_dir}/fullchain.pem" && -f "${secrets_dir}/privkey.pem" ]]; then
    if [[ -z "$TLS_MODE" || "$TLS_MODE" == "provided" ]]; then
      TLS_MODE="provided"
      TLS_CERT="${secrets_dir}/fullchain.pem"
      TLS_KEY="${secrets_dir}/privkey.pem"
      log "Certificado provisto detectado en .secrets/certs"
    fi
  fi

  if [[ -n "$TLS_CERT" || -n "$TLS_KEY" ]]; then
    [[ -n "$TLS_CERT" && -n "$TLS_KEY" ]] || die "Usá --cert y --key juntos"
    if [[ -n "$TLS_MODE" && "$TLS_MODE" != "provided" ]]; then
      die "--cert/--key requieren --tls-mode provided"
    fi
    TLS_MODE="provided"
  fi

  TLS_MODE="${TLS_MODE:-self_signed}"
  case "$TLS_MODE" in
    self_signed|provided|disabled) ;;
    *) die "Modo TLS inválido: $TLS_MODE (usá self_signed, provided o disabled)";;
  esac

  if [[ "$TLS_MODE" == "provided" ]]; then
    [[ -n "$TLS_CERT" && -n "$TLS_KEY" ]] || die "certs_mode=provided requiere --cert y --key"
    [[ -f "$TLS_CERT" ]] || die "No existe el certificado: $TLS_CERT"
    [[ -f "$TLS_KEY" ]] || die "No existe la clave: $TLS_KEY"
    TLS_CERT="$(realpath "$TLS_CERT")"
    TLS_KEY="$(realpath "$TLS_KEY")"
  fi

  EXTRA_VARS+=(-e "certs_mode=$TLS_MODE")
  if [[ -n "$TLS_HOSTNAME" ]]; then
    EXTRA_VARS+=(-e "certs_hostname=$TLS_HOSTNAME")
  fi
  if [[ -n "$TLS_CERT" ]]; then
    EXTRA_VARS+=(-e "certs_external_cert=$TLS_CERT")
    EXTRA_VARS+=(-e "certs_external_key=$TLS_KEY")
  fi
  if [[ "$TLS_FORCE" == "1" || "$TLS_FORCE" == "true" ]]; then
    EXTRA_VARS+=(-e "certs_force=true")
  fi
}

confirm_if_reset_data() {
  (( RESET_DATA )) || return 0
  warn "--reset-data eliminará los volúmenes de PostgreSQL y Ollama."
  (( ASSUME_YES )) && return 0
  local ans=""
  read -r -p "Escribí 'reset-data' para continuar: " ans </dev/tty || die "Cancelado"
  [[ "$ans" == "reset-data" ]] || die "Cancelado"
}

prepare_backend_source() {
  local raw_src="$1"
  local clean_src="${TMP_DIR}/anomalia-backend"
  mkdir -p "$clean_src"
  tar -C "$raw_src" "${BACKEND_SOURCE_EXCLUDES[@]}" -cf - . | tar -C "$clean_src" -xf -
  BACKEND_SRC="$clean_src"
}

prepare_backend() {
  local raw_src
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/anomalia-deploy.XXXXXX")"
  if [[ -n "$BACKEND_SRC" ]]; then
    [[ -d "$BACKEND_SRC" ]] || die "No existe backend: $BACKEND_SRC"
    raw_src="$(cd -- "$BACKEND_SRC" && pwd)"
    log "Usando checkout local: $raw_src"
  else
    raw_src="${TMP_DIR}/anomalia-backend-original"
    log "Clonando backend: $BACKEND_REPO (ref=$BACKEND_REF)"
    GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" git clone --depth 1 --branch "$BACKEND_REF" "$BACKEND_REPO" "$raw_src"
  fi
  log "Preparando copia limpia del backend para el deploy"
  prepare_backend_source "$raw_src"
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
  (cd "$REPO_ROOT" && ansible-playbook -i "$INVENTORY" deploy-infra.yml --syntax-check "${EXTRA_VARS[@]}")
  log "Desplegando"
  (cd "$REPO_ROOT" && ansible-playbook -i "$INVENTORY" deploy-infra.yml -e "anomalia_backend_src=$BACKEND_SRC" "${EXTRA_VARS[@]}")
}

deploy_tls() {
  log "Verificando sintaxis de la renovación TLS"
  (cd "$REPO_ROOT" && ansible-playbook -i "$INVENTORY" deploy-tls.yml --syntax-check "${EXTRA_VARS[@]}")
  log "Renovando certificados y recargando el gateway"
  (cd "$REPO_ROOT" && ansible-playbook -i "$INVENTORY" deploy-tls.yml "${EXTRA_VARS[@]}")
}

show_status() {
  log "Estado"
  command -v docker >/dev/null && docker ps --format 'table {{.Names}}\t{{.Status}}' || true
  systemctl list-units 'anomalia-*' --all --no-pager 2>/dev/null || true
  if grep -q 'ansible_connection=local' "$INVENTORY" 2>/dev/null; then
    for u in "http://127.0.0.1:8000/healthz" "http://127.0.0.1:8427/health" "http://127.0.0.1:8090/"; do
      curl -fsS --max-time 3 "$u" >/dev/null 2>&1 && echo "OK    $u" || echo "AVISO $u sin respuesta"
    done
    if [[ "$TLS_MODE" == "disabled" ]]; then
      u="http://127.0.0.1/healthz"
      curl -fsSL --max-time 3 "$u" >/dev/null 2>&1 && echo "OK    $u" || echo "AVISO $u sin respuesta"
    else
      u="https://127.0.0.1/healthz"
      curl -fsSk --max-time 3 "$u" >/dev/null 2>&1 && echo "OK    $u" || echo "AVISO $u sin respuesta"
    fi
  fi
}

main() {
  parse_args "$@"
  preflight
  resolve_inventory
  check_inventory_placeholders
  resolve_tls
  (( ASSUME_YES )) && EXTRA_VARS+=(-e "anomalia_assume_yes=1")
  (( RESET_DATA )) && EXTRA_VARS+=(-e "anomalia_compose_destroy_volumes=1")
  if (( TLS_ONLY )); then
    deploy_tls
    show_status
    log "Renovación TLS completada"
    return 0
  fi
  announce_token_source
  confirm_if_reset_data
  prepare_backend
  deploy
  show_status
  log "Deploy completado"
}

main "$@"
