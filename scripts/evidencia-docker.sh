#!/usr/bin/env bash
# Agrega a evidence/ la verificación con Docker de los incidentes 1, 2, 5, 6 y 10.
# Ejecuta ./reset.sh (borra contenedores, base y output/), levanta todo desde cero,
# corre el cierre dos veces y guarda cada comando con su salida real.
# Uso: ./scripts/evidencia-docker.sh   (requiere Docker y curl)
set -uo pipefail
cd "$(dirname "$0")/.."

# Escribe "$ comando", su salida y el código de salida, como el resto de evidence/.
ev() {
    echo "\$ $*"
    bash -c "$*" 2>&1
    echo "[codigo de salida: $?]"
    echo
}

# Quita la nota "pendiente" del archivo y agrega la sección de verificación.
agregar() {
    local archivo="evidence/$1"
    sed -i -e '/pendiente de pegar/d' -e '/^# docker compose exec/d' "$archivo"
    {
        echo "# Verificacion con Docker ($(date '+%Y-%m-%d %H:%M'))"
        cat
    } >> "$archivo"
    echo ">> Actualizado $archivo"
}

./reset.sh

echo ">> Esperando a que cierre-api responda"
for _ in $(seq 1 30); do
    curl -s -o /dev/null http://localhost:8081/health && break
    sleep 2
done

{
    ev "docker compose ps"
    ev "docker compose logs cierre-worker | tail -5"
} | agregar 01-worker.txt

{
    ev "docker compose logs cierre-api | tail -3"
    ev "curl -s -i http://localhost:8081/afiliados/1098765432"
} | agregar 02-api-db.txt

{
    ev "docker compose exec -T cierre-db psql -U cierre -d cierre -c 'SELECT count(*) AS registros, count(DISTINCT nro_doc) AS documentos FROM afi_mae'"
} | agregar 05-calidad-datos.txt

{
    ev "curl -s -i http://localhost:8081/afiliados/3756530718"
    ev "curl -s -i http://localhost:8081/afiliados/88121168"
    ev "curl -s -i http://localhost:8081/afiliados/0000000001"
} | agregar 06-api-500.txt

{
    ev "./run.sh > /dev/null && md5sum output/* | tee /tmp/despues-reset-1.txt"
    ev "./run.sh > /dev/null && md5sum output/* | tee /tmp/despues-reset-2.txt"
    ev "diff /tmp/despues-reset-1.txt /tmp/despues-reset-2.txt && echo IDENTICAS"
} | agregar 10-repetible.txt
