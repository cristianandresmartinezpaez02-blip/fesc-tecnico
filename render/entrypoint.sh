#!/bin/sh
# Arranque de cierre-api en Render.
# Si la base está vacía (no existe afi_mae), crea el esquema, carga data/ y aplica
# la limpieza, todo en una sola transacción: si algo falla no queda a medias.
# Después inicia la API. En arranques siguientes la carga se omite.
set -e

if [ -n "${DATABASE_URL:-}" ]; then
    existe="$(psql "$DATABASE_URL" -tAc "SELECT to_regclass('public.afi_mae') IS NOT NULL")"
    if [ "$existe" != "t" ]; then
        echo "Base vacía: creando esquema y cargando data/"
        psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q --single-transaction \
            -f /app/db-init/01_schema.sql \
            -f /app/db-init/02_load.sql \
            -f /app/db-init/03_limpieza.sql
        echo "Carga terminada"
    fi
fi

exec python app.py
