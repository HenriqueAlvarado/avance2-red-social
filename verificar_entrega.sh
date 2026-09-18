#!/bin/bash
# ============================================================
# Verificador de entrega — Avance 2
# Revisa que todos los archivos requeridos existan y no tengan
# el placeholder [COMPLETAR] sin reemplazar
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

PENDIENTES=0

check() {
  local archivo="$1"
  if [ -f "$archivo" ]; then
    if grep -q "\[COMPLETAR\]" "$archivo" 2>/dev/null; then
      echo -e "${YELLOW}⚠️  INCOMPLETO:${NC} $archivo  (contiene [COMPLETAR])"
      PENDIENTES=$((PENDIENTES + 1))
    else
      echo -e "${GREEN}✅${NC} $archivo"
    fi
  else
    echo -e "${RED}❌ FALTA:${NC} $archivo"
    PENDIENTES=$((PENDIENTES + 1))
  fi
}

echo -e "\n${BOLD}Verificando entrega Avance 2...${NC}\n"

# Código y contenedores
check "app/app.py"
check "app/requirements.txt"
check "app/Dockerfile"
check "docker-compose.yml"

# Infraestructura
check "infra/main.tf"
check "infra/variables.tf"
check "infra/outputs.tf"

# Pipeline
check "pipeline/pipeline.sh"

# Reportes
check "reportes/corrida_roja.txt"
check "reportes/corrida_verde.txt"
check "reportes/sbom_cyclonedx.json"

# Documentación
check "docs/README.md"
check "docs/diagrama_arquitectura.png"
check "docs/ADR-001-decisiones-tecnicas.md"
check "docs/tabla_decisiones_pipeline.md"
check "docs/declaracion_uso_ia.md"

# Raíz
check ".gitignore"

# Verificar que .env NO esté en el repo
if [ -f ".env" ] && git ls-files --error-unmatch .env 2>/dev/null; then
  echo -e "${RED}🚨 CRÍTICO: .env está siendo rastreado por Git${NC}"
  PENDIENTES=$((PENDIENTES + 1))
fi

# Verificar que .env esté en .gitignore
if grep -q "^\.env$" .gitignore 2>/dev/null; then
  echo -e "${GREEN}✅${NC} .env está en .gitignore"
else
  echo -e "${RED}❌ .env no está en .gitignore${NC}"
  PENDIENTES=$((PENDIENTES + 1))
fi

echo ""
if [ "$PENDIENTES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}✅ Entrega completa. Todo en orden.${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}❌ $PENDIENTES elemento(s) pendiente(s). Revisa los items marcados arriba.${NC}"
  exit 1
fi
