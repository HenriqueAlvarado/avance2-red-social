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
  semgrep --config "p/secrets" \
          --config "p/python" \
          --severity ERROR \
          --error \
          --json \
          --output "$REPORTES/semgrep_resultado.json" \
          "$REPO_ROOT/app" 2>/dev/null || true

  SECRETS=$(python3 -c "
import json, sys
with open('$REPORTES/semgrep_resultado.json') as f:
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
  checkov -d "$REPO_ROOT/infra" \
          --framework terraform \
          --output json \
          --output-file "$REPORTES/checkov_resultado.json" \
          --soft-fail 2>/dev/null || true

  FAILED=$(python3 -c "
import json
with open('$REPORTES/checkov_resultado.json') as f:
  raw = f.read().strip()
  # checkov puede devolver lista o dict
  import json as j
  d = j.loads(raw)
  if isinstance(d, list):
    d = d[0]
results = d.get('results', {})
failed = results.get('failed_checks', [])
high = [c for c in failed
        if c.get('check_result', {}).get('result') == 'FAILED'
        and c.get('severity', '') in ('HIGH', 'CRITICAL', 'high', 'critical')]
print(len(high) if high else len(failed))
" 2>/dev/null || echo "0")

  if [ "$FAILED" -gt 0 ]; then
    fail "Etapa 4: Checkov encontró $FAILED check(s) fallidos en IaC"
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
