#!/usr/bin/env bash
# Punto de entrada del cierre mensual. El validador ejecuta este archivo.
# 1) Si cierre-db está arriba, aplica la limpieza de datos en la base (idempotente).
# 2) Ejecuta el cierre, que lee data/ y genera los 4 archivos de output/.
set -euo pipefail
cd "$(dirname "$0")"

# Se guarda la lista de servicios antes de buscar: con pipefail, "docker ... | grep -q"
# puede fallar por SIGPIPE aunque cierre-db sí esté corriendo.
SERVICIOS_ACTIVOS="$(command -v docker >/dev/null 2>&1 && docker compose ps --status running --services 2>/dev/null || true)"
if printf '%s\n' "$SERVICIOS_ACTIVOS" | grep -qx cierre-db; then
    echo ">> Aplicando limpieza de datos en cierre-db"
    docker compose exec -T cierre-db sh -c 'psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /docker-entrypoint-initdb.d/03_limpieza.sql' \
        || echo "AVISO: no se pudo aplicar la limpieza en la base; el cierre continúa con data/" >&2
fi

bash ./scripts/cierre.sh
