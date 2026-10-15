#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Cierre mensual de afiliados activos.
# Lee los CSV del sistema origen (data/), aplica las reglas de docs/diccionario.md
# y genera en output/: afiliados_activos.csv, excepciones.csv, totales.txt y
# top_error.txt.
#
# Es repetible: no mueve ni borra la entrada, sobrescribe las salidas (nunca
# agrega con >>) y ordena todo de forma determinista. Dos ejecuciones seguidas
# producen archivos idénticos byte a byte.
# ---------------------------------------------------------------------------
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
ENTRADA="${CIERRE_ENTRADA:-$RAIZ/data}"
SALIDA="${CIERRE_SALIDA:-$RAIZ/output}"
LOGS="${CIERRE_LOGS:-$RAIZ/logs}"

# Orden y comparación de texto independientes del idioma del servidor.
export LC_ALL=C

for archivo in AFI_MAE.csv AFI_BEN.csv APORTES.csv EMPRESA.csv extracto_caja_oriente.csv; do
    if [ ! -r "$ENTRADA/$archivo" ]; then
        echo "ERROR: no se puede leer $ENTRADA/$archivo (revise ruta y permisos)" >&2
        exit 1
    fi
done

mkdir -p "$SALIDA"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Leyendo afiliados desde $ENTRADA/AFI_MAE.csv"

# Quita retornos de carro por si algún CSV llega con finales de línea de Windows.
for archivo in AFI_MAE.csv AFI_BEN.csv APORTES.csv EMPRESA.csv extracto_caja_oriente.csv; do
    tr -d '\r' < "$ENTRADA/$archivo" > "$TMP/$archivo"
done

awk -v SALIDA="$TMP" '
# Fecha real en calendario gregoriano (año, mes, día numéricos).
function fecha_real(y, m, d,    dias) {
    if (y < 1 || m < 1 || m > 12 || d < 1) return 0
    dias = substr("312831303130313130313031", (m - 1) * 2 + 1, 2) + 0
    if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) dias = 29
    return d <= dias
}
# Normaliza FEC_AFI a YYYY-MM-DD; devuelve "" si no se puede interpretar.
function normaliza_fecha(f,    y, m, d) {
    if (f ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
        y = substr(f, 1, 4); m = substr(f, 6, 2); d = substr(f, 9, 2)
    } else if (f ~ /^[0-9][0-9]\/[0-9][0-9]\/[0-9][0-9][0-9][0-9]$/) {
        d = substr(f, 1, 2); m = substr(f, 4, 2); y = substr(f, 7, 4)
    } else if (f ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) {
        y = substr(f, 1, 4); m = substr(f, 5, 2); d = substr(f, 7, 2)
    } else {
        return ""
    }
    if (!fecha_real(y + 0, m + 0, d + 0)) return ""
    return y "-" m "-" d
}
# Campo CSV: se entrecomilla solo si trae coma o comillas.
function csv(v) {
    if (v ~ /[",]/) { gsub(/"/, "\"\"", v); return "\"" v "\"" }
    return v
}
function excepcion(documento, tipo, detalle) {
    nexc++
    exc[nexc] = csv(documento) "," tipo "," csv(detalle)
}

FILENAME ~ /EMPRESA\.csv$/ {
    if (FNR > 1 && $1 != "" && !($1 in empresa)) empresa[$1] = $2
    next
}

FILENAME ~ /AFI_MAE\.csv$/ {
    if (FNR == 1) next
    doc = $1
    if (doc in visto) {
        # Regla 1: se conserva la primera aparición; DUPLICADO una vez por documento.
        if (!(doc in duplicado)) { duplicado[doc] = 1; ndup++; dup[ndup] = doc }
        apariciones[doc]++
        next
    }
    visto[doc] = 1
    apariciones[doc] = 1
    nafi++
    orden[nafi] = doc
    nombre = $3
    if ($4 != "") nombre = nombre " " $4
    if ($5 != "") nombre = nombre " " $5
    if ($6 != "") nombre = nombre " " $6
    nom[doc] = nombre
    est[doc] = $7
    emp[doc] = $8
    fec[doc] = $9
    next
}

FILENAME ~ /AFI_BEN\.csv$/ {
    if (FNR == 1) next
    nben++
    ben_doc[nben] = $1
    ben_afi[nben] = $2
    nbenef[$2]++
    next
}

FILENAME ~ /APORTES\.csv$/ {
    if (FNR == 1) next
    if ($2 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]$/ && (!($1 in ultimo) || $2 > ultimo[$1])) ultimo[$1] = $2
    next
}

FILENAME ~ /extracto_caja_oriente\.csv$/ {
    if (FNR == 1) next
    ncru++
    cru_doc[ncru] = $1
    cru_sit[ncru] = $3
    next
}

END {
    activos = 0; inactivos = 0
    print "documento,nombre,estado,cod_empresa,empresa,beneficiarios,ultimo_aporte" > (SALIDA "/afiliados_activos.csv")

    for (i = 1; i <= ndup; i++)
        excepcion(dup[i], "DUPLICADO", "aparece " apariciones[dup[i]] " veces en AFI_MAE; se conserva la primera")

    for (i = 1; i <= nafi; i++) {
        doc = orden[i]
        e = est[doc]
        # Regla 5: la fecha nunca excluye; se normaliza o se reporta.
        if (normaliza_fecha(fec[doc]) == "")
            excepcion(doc, "FECHA_INVALIDA", "FEC_AFI no interpretable: " fec[doc])
        if (e == "A") {
            if (emp[doc] == "" || !(emp[doc] in empresa)) {
                # Regla 3: activo sin empresa válida no entra al archivo ni al total.
                excepcion(doc, "SIN_EMPRESA", (emp[doc] == "" ? "COD_EMP vacio" : "COD_EMP " emp[doc] " no existe en EMPRESA"))
                continue
            }
            activos++
            print csv(doc) "," csv(nom[doc]) ",ACTIVO," csv(emp[doc]) "," csv(empresa[emp[doc]]) "," (nbenef[doc] + 0) "," ultimo[doc] > (SALIDA "/afiliados_activos.csv")
        } else if (e == "I") {
            inactivos++
        } else {
            # Regla 2: ni activo ni inactivo.
            excepcion(doc, "CODIGO_INVALIDO", "EST_AFI " e " no es A ni I")
        }
    }

    # Regla 4: beneficiario cuyo afiliado no existe (una vez por beneficiario).
    for (i = 1; i <= nben; i++) {
        if (!(ben_afi[i] in visto) && !(ben_doc[i] in huerfano)) {
            huerfano[ben_doc[i]] = 1
            excepcion(ben_doc[i], "BENEFICIARIO_HUERFANO", "NRO_DOC_AFI " ben_afi[i] " no existe en AFI_MAE")
        }
    }

    # Regla 6: cruce con Caja Oriente (documento de 12 dígitos con ceros a la izquierda).
    for (i = 1; i <= ncru; i++) {
        doc = cru_doc[i]
        sub(/^0+/, "", doc)
        if (doc in cruzado) continue
        cruzado[doc] = 1
        sit = cru_sit[i]
        if (!(doc in visto)) {
            excepcion(doc, "CRUCE_NO_COINCIDE", "Caja Oriente reporta " sit "; no existe en AFI_MAE")
        } else {
            esperado = (sit == "VIGENTE") ? "A" : ((sit == "RETIRADO") ? "I" : "")
            if (est[doc] != esperado)
                excepcion(doc, "CRUCE_NO_COINCIDE", "Caja Oriente reporta " sit "; EST_AFI local " est[doc])
        }
    }

    print "documento,tipo,detalle" > (SALIDA "/excepciones.csv")
    for (i = 1; i <= nexc; i++) print exc[i] > (SALIDA "/excepciones.csv")

    # Regla 8: totales.
    print "total_afiliados=" nafi > (SALIDA "/totales.txt")
    print "activos=" activos > (SALIDA "/totales.txt")
    print "inactivos=" inactivos > (SALIDA "/totales.txt")
    print "excepciones=" nexc > (SALIDA "/totales.txt")
}
' FS=',' "$TMP/EMPRESA.csv" "$TMP/AFI_MAE.csv" "$TMP/AFI_BEN.csv" "$TMP/APORTES.csv" \
  FS=';' "$TMP/extracto_caja_oriente.csv"

# Error más frecuente de los tres logs: códigos CIE-#### (los avisos W-### no son errores).
# Empate: gana el código menor para que el resultado sea estable.
TOP="$(cat "$LOGS"/*.log | grep -o 'CIE-[0-9][0-9][0-9][0-9]' | sort | uniq -c | sort -k1,1nr -k2,2 | head -n 1 || true)"
if [ -z "$TOP" ]; then
    printf 'codigo_error=\nocurrencias=0\n' > "$TMP/top_error.txt"
else
    echo "$TOP" | awk '{ print "codigo_error=" $2; print "ocurrencias=" $1 }' > "$TMP/top_error.txt"
fi
cp "$TMP/top_error.txt" "$SALIDA/top_error.txt"

# Las salidas se escriben primero en un temporal y se copian al final:
# si algo falla a mitad de camino, output/ no queda a medias.
for archivo in afiliados_activos.csv excepciones.csv totales.txt; do
    cp "$TMP/$archivo" "$SALIDA/$archivo"
done

echo "Cierre terminado:"
cat "$SALIDA/totales.txt"
cat "$SALIDA/top_error.txt"
