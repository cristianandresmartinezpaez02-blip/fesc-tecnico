-- Limpieza de calidad de datos (incidentes 5 y 7). Se ejecuta al crear la base
-- y run.sh la vuelve a aplicar: es idempotente, correrla dos veces no cambia nada.
-- Lo irreparable (SIN_EMPRESA, CODIGO_INVALIDO, BENEFICIARIO_HUERFANO,
-- FECHA_INVALIDA) no se borra: lo reporta output/excepciones.csv.

-- 1. Duplicados: se conserva la primera aparición de cada documento (la de menor
--    ctid, es decir, la primera fila cargada desde AFI_MAE.csv).
DELETE FROM afi_mae a
USING afi_mae b
WHERE a.nro_doc = b.nro_doc
  AND a.ctid > b.ctid;

-- Evita que vuelvan a entrar duplicados.
CREATE UNIQUE INDEX IF NOT EXISTS uq_afi_mae_doc ON afi_mae (nro_doc);

-- 2. Fechas: DD/MM/YYYY y YYYYMMDD se normalizan a YYYY-MM-DD. Si el texto no es
--    una fecha real devuelve NULL y el valor original se deja intacto.
CREATE OR REPLACE FUNCTION normaliza_fecha(t TEXT) RETURNS TEXT AS $$
DECLARE
    iso TEXT;
BEGIN
    IF t ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        iso := t;
    ELSIF t ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN
        iso := substr(t, 7, 4) || '-' || substr(t, 4, 2) || '-' || substr(t, 1, 2);
    ELSIF t ~ '^[0-9]{8}$' THEN
        iso := substr(t, 1, 4) || '-' || substr(t, 5, 2) || '-' || substr(t, 7, 2);
    ELSE
        RETURN NULL;
    END IF;
    PERFORM iso::date;
    RETURN iso;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

UPDATE afi_mae
SET fec_afi = normaliza_fecha(fec_afi)
WHERE normaliza_fecha(fec_afi) IS NOT NULL
  AND fec_afi <> normaliza_fecha(fec_afi);
