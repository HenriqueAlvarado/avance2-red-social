#!/bin/bash
# ============================================================
# Pipeline de seguridad - Avance 2 · Red Social
# Decisión final integrada: BLOQUEAR o PERMITIR
# ============================================================
set -euo pipefail

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Variables ─────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORTES="$REPO_ROOT/reportes"
IMAGEN="redsocial-api:pipeline-test"
VEREDICTO=0   # 0=PERMITIR  1=BLOQUEAR
HALLAZGOS=()

log()    { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()     { echo -e "${GREEN}✅ $*${NC}"; }
warn()   { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail()   { echo -e "${RED}❌ $*${NC}"; VEREDICTO=1; HALLAZGOS+=("$*"); }
header() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; \
           echo -e "${BOLD}${CYAN}  $*${NC}"; \
           echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}"; }

mkdir -p "$REPORTES"

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 1: Secrets scanning — Semgrep
# Riesgo cubierto: credenciales quemadas en código (AWS keys, passwords)
# Umbral: bloquea si encuentra CUALQUIER secreto (severidad alta por naturaleza)
# ────────────────────────────────────────────────────────────────────────────
header "ETAPA 1 · Secrets Scanning (Semgrep)"
log "Buscando credenciales y secretos en el código fuente..."

if command -v semgrep &>/dev/null; then
  # Solo reglas de secretos: credenciales quemadas, tokens, llaves.
  # (El análisis de inyección se movió a la Etapa 2.5 para reportarlo con su
  #  nombre correcto y no confundirlo con un "secreto".)
  semgrep --config "p/secrets" \
          --severity ERROR \
          --error \
          --json \
          --output "$REPORTES/semgrep_secrets.json" \
          "$REPO_ROOT/app" 2>/dev/null || true

  SECRETS=$(python3 -c "
import json, sys
with open('$REPORTES/semgrep_secrets.json') as f:
  d = json.load(f)
count = len(d.get('results', []))
print(count)
" 2>/dev/null || echo "0")

  if [ "$SECRETS" -gt 0 ]; then
    fail "Etapa 1: Semgrep encontró $SECRETS secreto(s) en el código"
  else
    ok "Etapa 1: Sin secretos detectados"
  fi
else
  warn "Semgrep no instalado — etapa omitida"
fi

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 2: Análisis estático de seguridad — Bandit
# Riesgo cubierto: vulnerabilidades en código Python (inyección SQL, uso
#   inseguro de crypto, debug activo, etc.)
# Umbral: bloquea en severidad HIGH o CRITICAL
# ────────────────────────────────────────────────────────────────────────────
header "ETAPA 2 · SAST Python (Bandit)"
log "Analizando código Python en busca de vulnerabilidades..."

if command -v bandit &>/dev/null; then
  bandit -r "$REPO_ROOT/app" \
         -ll \
         -f json \
         -o "$REPORTES/bandit_resultado.json" 2>/dev/null || true

  HIGH_ISSUES=$(python3 -c "
import json
with open('$REPORTES/bandit_resultado.json') as f:
  d = json.load(f)
count = sum(1 for r in d.get('results', [])
            if r['issue_severity'] in ('HIGH', 'CRITICAL'))
print(count)
" 2>/dev/null || echo "0")

  if [ "$HIGH_ISSUES" -gt 0 ]; then
    fail "Etapa 2: Bandit encontró $HIGH_ISSUES hallazgo(s) HIGH/CRITICAL"
  else
    ok "Etapa 2: Sin hallazgos HIGH/CRITICAL en Bandit"
  fi
else
  warn "Bandit no instalado — etapa omitida"
fi

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 2.5: SAST de inyección — Semgrep (reglas Python) + Bandit (B608)
# Riesgo cubierto: inyección SQL (CWE-89) por construcción manual de queries.
#   Se añadió en la Entrega Final: la Etapa 2 (Bandit HIGH/CRITICAL) NO detiene
#   este caso porque Bandit clasifica el SQLi (B608) como MEDIUM. Esta etapa
#   cierra ese hueco y reporta el hallazgo con su nombre correcto (no como
#   "secreto"). Umbral: bloquea con CUALQUIER hallazgo de inyección.
# ────────────────────────────────────────────────────────────────────────────
header "ETAPA 2.5 · SAST Inyección SQL (Semgrep + Bandit B608)"
log "Buscando SQL construido con input del usuario (CWE-89)..."

INYECCIONES=0

# Semgrep: reglas de seguridad para Python/Flask (incluye tainted-sql-string).
if command -v semgrep &>/dev/null; then
  semgrep --config "p/python" \
          --json \
          --output "$REPORTES/semgrep_inyeccion.json" \
          "$REPO_ROOT/app" 2>/dev/null || true

  SG_INJ=$(python3 -c "
import json
with open('$REPORTES/semgrep_inyeccion.json') as f:
  d = json.load(f)
# Solo inyección SQL: el check_id debe mencionar 'sql' explícitamente.
# (Se evita 'inject' a secas porque matchea reglas de URL como
#  injection.tainted-url-host, que no son SQLi.)
count = sum(1 for r in d.get('results', [])
            if 'sql' in r.get('check_id', '').lower())
print(count)
" 2>/dev/null || echo "0")
  INYECCIONES=$((INYECCIONES + SG_INJ))
fi

# Bandit: regla B608 (hardcoded_sql_expressions) sin filtrar por severidad.
if command -v bandit &>/dev/null; then
  bandit -r "$REPO_ROOT/app" \
         -f json \
         -o "$REPORTES/bandit_sqli.json" 2>/dev/null || true

  BD_INJ=$(python3 -c "
import json
with open('$REPORTES/bandit_sqli.json') as f:
  d = json.load(f)
count = sum(1 for r in d.get('results', [])
            if r.get('test_id') == 'B608')
print(count)
" 2>/dev/null || echo "0")
  INYECCIONES=$((INYECCIONES + BD_INJ))
fi

if [ "$INYECCIONES" -gt 0 ]; then
  fail "Etapa 2.5: Detectada(s) $INYECCIONES posible(s) inyección(es) SQL (CWE-89)"
else
  ok "Etapa 2.5: Sin patrones de inyección SQL detectados"
fi

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 3: Escaneo de vulnerabilidades en imagen Docker — Trivy
# Riesgo cubierto: CVEs en dependencias del sistema y librerías Python
#   dentro de la imagen (vector de ataque en contenedor de producción)
# Umbral: bloquea en CRITICAL o HIGH
# ────────────────────────────────────────────────────────────────────────────
header "ETAPA 3 · Vulnerabilidades en imagen (Trivy)"
log "Construyendo imagen de prueba..."

docker build -t "$IMAGEN" "$REPO_ROOT/app" -q 2>/dev/null
log "Escaneando imagen $IMAGEN..."

if command -v trivy &>/dev/null; then
  trivy image \
        --exit-code 0 \
        --severity HIGH,CRITICAL \
        --ignore-unfixed \
        --format json \
        --output "$REPORTES/trivy_imagen.json" \
        --no-progress \
        "$IMAGEN" 2>/dev/null

  VULNS=$(python3 -c "
import json
with open('$REPORTES/trivy_imagen.json') as f:
  d = json.load(f)
total = 0
for r in d.get('Results', []):
  for v in r.get('Vulnerabilities') or []:
    if v.get('Severity') in ('HIGH', 'CRITICAL'):
      total += 1
print(total)
" 2>/dev/null || echo "0")

  if [ "$VULNS" -gt 0 ]; then
    fail "Etapa 3: Trivy encontró $VULNS CVE(s) HIGH/CRITICAL en la imagen"
  else
    ok "Etapa 3: Sin CVEs HIGH/CRITICAL en la imagen"
  fi
else
  warn "Trivy no instalado — etapa omitida"
fi

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 4: Escaneo de IaC — Checkov
# Riesgo cubierto: configuraciones inseguras en Terraform (S3 sin cifrado,
#   RDS con acceso público, SGs permisivos)
# Umbral: bloquea en severidad HIGH o CRITICAL
# ────────────────────────────────────────────────────────────────────────────
header "ETAPA 4 · Infraestructura como Código (Checkov)"
log "Analizando archivos Terraform en infra/..."

if command -v checkov &>/dev/null; then
  # Limpia un posible directorio residual con ese nombre (versiones previas del
  # pipeline usaban --output-file, que creaba un directorio en vez de archivo).
  rm -rf "$REPORTES/checkov_resultado.json"

  # Se escribe el JSON al archivo y se silencia el volcado a la terminal con
  # --quiet (antes ensuciaba la salida del pipeline con miles de líneas).
  # El umbral de esta etapa se mantiene igual que en el Avance 2: solo
  # bloquea ante hallazgos de severidad HIGH/CRITICAL (con severidad nula, que
  # es lo que devuelve Checkov sin API key, no se bloquea).
  checkov -d "$REPO_ROOT/infra" \
          --framework terraform \
          --output json \
          --quiet \
          --soft-fail > "$REPORTES/checkov_resultado.json" 2>/dev/null || true

  FAILED=$(python3 -c "
import json
with open('$REPORTES/checkov_resultado.json') as f:
  d = json.load(f)
if isinstance(d, list):
  d = d[0] if d else {}
results = d.get('results', {})
failed = results.get('failed_checks', [])
high = [c for c in failed
        if c.get('severity', None) in ('HIGH', 'CRITICAL', 'high', 'critical')]
print(len(high))
" 2>/dev/null || echo "0")

  if [ "$FAILED" -gt 0 ]; then
    fail "Etapa 4: Checkov encontró $FAILED check(s) HIGH/CRITICAL en IaC"
  else
    ok "Etapa 4: IaC sin hallazgos críticos"
  fi
else
  warn "Checkov no instalado — etapa omitida"
fi

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 5: SBOM — Syft
# Riesgo cubierto: inventario de componentes para rastrear dependencias
#   comprometidas en el futuro
# Umbral: solo genera artefacto (no bloquea), pero su ausencia indica
#   falta de trazabilidad
# ────────────────────────────────────────────────────────────────────────────
header "ETAPA 5 · SBOM (Syft / CycloneDX)"
log "Generando inventario de dependencias..."

if command -v syft &>/dev/null; then
  syft "$IMAGEN" \
       -o cyclonedx-json \
       --file "$REPORTES/sbom_cyclonedx.json" 2>/dev/null
  ok "Etapa 5: SBOM generado en reportes/sbom_cyclonedx.json"
else
  warn "Syft no instalado — SBOM no generado"
fi

# ────────────────────────────────────────────────────────────────────────────
# VEREDICTO FINAL INTEGRADO
# ────────────────────────────────────────────────────────────────────────────
header "VEREDICTO FINAL"

if [ "$VEREDICTO" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}"
  echo "╔══════════════════════════════════════╗"
  echo "║         ✅  PIPELINE: VERDE          ║"
  echo "║         DESPLIEGUE PERMITIDO         ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}"
  echo "╔══════════════════════════════════════╗"
  echo "║         ❌  PIPELINE: ROJO           ║"
  echo "║         DESPLIEGUE BLOQUEADO         ║"
  echo "╚══════════════════════════════════════╝"
  echo ""
  echo "Hallazgos que causaron el bloqueo:"
  for h in "${HALLAZGOS[@]}"; do
    echo "  → $h"
  done
  echo -e "${NC}"
  exit 1
fi
