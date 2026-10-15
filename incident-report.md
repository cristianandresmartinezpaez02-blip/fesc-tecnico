# Informe de incidentes — Terminal Rescue

## Incidente 1
- **Síntoma:** `docker compose ps` muestra `cierre-worker` en `Exited (1)` y el worker nunca concilia.
- **Diagnóstico:** el log del worker repite el código CIE-1107 (158 veces): `WORKER_INTERVAL_SECONDS` debe ser un entero de segundos y `.env.example` traía `30s`, así que `int("30s")` falla y el proceso hace `sys.exit(1)`.
- **Comandos:** `docker compose ps`, `docker compose logs cierre-worker | tail -5`, `grep -c 'CIE-1107' logs/worker.log`, `grep -n 'int(raw)' services/worker/worker.py`, `grep -n WORKER_INTERVAL_SECONDS .env.example`
- **Solución:** `WORKER_INTERVAL_SECONDS=30` en `.env.example` (el `.env` se crea copiándolo) y reinicio con `docker compose up -d`.
- **Evidencia:** evidence/01-worker.txt

## Incidente 2
- **Síntoma:** la API no conecta a la base: las consultas fallan con CIE-2210 y responden 503.
- **Diagnóstico:** `DATABASE_HOST=cierre-database` apunta a un nombre que no existe en la red de Docker Compose; el servicio de PostgreSQL se llama `cierre-db`. Entre contenedores se usa el nombre del servicio, no `localhost`.
- **Comandos:** `grep -c 'CIE-2210' logs/*.log`, `grep -n DATABASE_HOST .env.example`, `grep -E '^  [a-z-]+:$' docker-compose.yml`, `docker compose logs cierre-api | grep CIE-2210`
- **Solución:** `DATABASE_HOST=cierre-db` en `.env.example`; lo usan cierre-api y cierre-worker.
- **Evidencia:** evidence/02-api-db.txt

## Incidente 3
- **Síntoma:** `./run.sh` termina con error: `awk: cannot open file /opt/cierre/entrada/AFI_MAE.csv`.
- **Diagnóstico:** el script heredado leía de `/opt/cierre/entrada`, una ruta del servidor viejo que no existe; los CSV están en `data/` del repositorio. Además los scripts necesitan permiso de ejecución en el servidor Linux.
- **Comandos:** `ls -l /opt/cierre/entrada`, `find . -name 'AFI_MAE.csv'`, `grep -n 'ENTRADA=' scripts/cierre.sh`, `chmod +x run.sh scripts/cierre.sh`, `git ls-files -s run.sh scripts/cierre.sh`
- **Solución:** `scripts/cierre.sh` calcula la raíz del repositorio y lee `data/`; valida que cada archivo sea legible; `run.sh` y `scripts/cierre.sh` quedan como 100755 en Git.
- **Evidencia:** evidence/03-entrada.txt

## Incidente 4
- **Síntoma:** más de 11 000 líneas en `logs/` y nadie sabe cuál es el error principal.
- **Diagnóstico:** los errores de los tres servicios usan códigos `CIE-####` (los `W-###` son avisos). Contando los códigos de los tres logs, `CIE-4012` (lote rechazado por afiliado sin empresa) aparece 1424 veces; el total de códigos (3115) coincide con el total de líneas de error.
- **Comandos:** `wc -l logs/*.log`, `cat logs/*.log | grep -o 'CIE-[0-9][0-9][0-9][0-9]' | sort | uniq -c | sort -k1,1nr -k2,2`, `grep -c 'CIE-4012' logs/*.log`
- **Solución:** `scripts/cierre.sh` calcula el conteo con ese mismo pipeline y escribe `output/top_error.txt` con `codigo_error=CIE-4012` y `ocurrencias=1424`.
- **Evidencia:** evidence/04-top-error.txt

## Incidente 5
- **Síntoma:** documentos duplicados, afiliados sin empresa, beneficiarios huérfanos y códigos de estado inválidos en los datos.
- **Diagnóstico:** AFI_MAE tiene 1520 filas pero 1500 documentos distintos (20 duplicados); 14 filas con estado P, X, Z o 9; 18 activos con `COD_EMP` vacío o inexistente; 15 beneficiarios cuyo afiliado no existe.
- **Comandos:** `cut -d, -f1 data/AFI_MAE.csv | sort | uniq -d | wc -l`, `awk -F, 'NR>1{print $7}' data/AFI_MAE.csv | sort | uniq -c`, `awk -F, 'NR==FNR{...} !($2 in m)' data/AFI_MAE.csv data/AFI_BEN.csv | wc -l`, `docker compose exec cierre-db psql -U cierre -d cierre -c 'SELECT count(*), count(DISTINCT nro_doc) FROM afi_mae'`
- **Solución:** `db/init/03_limpieza.sql` borra duplicados en cierre-db conservando la primera aparición y crea un índice único; lo irreparable se reporta en `output/excepciones.csv` como DUPLICADO, SIN_EMPRESA, BENEFICIARIO_HUERFANO y CODIGO_INVALIDO.
- **Evidencia:** evidence/05-calidad-datos.txt

## Incidente 6
- **Síntoma:** `GET /afiliados/{documento}` responde 500 (700 errores CIE-5003 en `api.log`).
- **Diagnóstico:** la carga `FORMAT csv` deja NOM2 vacío como NULL (588 afiliados) y `nom1 + " " + nom2` falla con `None`. Además el `JOIN` daba 404 a afiliados sin empresa y `ESTADOS[est_afi]` fallaba con estados inválidos.
- **Comandos:** `grep -c 'CIE-5003' logs/api.log`, `awk -F, 'NR>1 && $4==""' data/AFI_MAE.csv | wc -l`, `grep -n 'JOIN' services/api/app.py`, `curl -i http://localhost:8081/afiliados/3756530718`
- **Solución:** en `services/api/app.py` el nombre se arma solo con las partes no vacías, se usa `LEFT JOIN` con empresa vacía si no hay, y `ESTADOS.get(...)` para estados no válidos.
- **Evidencia:** evidence/06-api-500.txt

## Incidente 7
- **Síntoma:** fechas de afiliación en formatos que el cierre no entiende (`DD/MM/YYYY`, `YYYYMMDD`, `SIN FECHA`, `N/A`).
- **Diagnóstico:** reemplazando dígitos por 9 aparecen 7 patrones; 18 fechas válidas vienen en `DD/MM/YYYY` o `YYYYMMDD` y 12 no son fechas reales (31/13/2024, 00000000, 2025-02-30, 2024-00-10, 2023/02/29, 15-15-2019, texto).
- **Comandos:** `cut -d, -f9 data/AFI_MAE.csv | sed 's/[0-9]/9/g' | sort | uniq -c`, `awk -F, 'NR>1 && $9 !~ /^[0-9]{4}-/' data/AFI_MAE.csv`, `grep -c FECHA_INVALIDA output/excepciones.csv`
- **Solución:** el cierre normaliza a `YYYY-MM-DD` validando calendario (años bisiestos) y reporta `FECHA_INVALIDA`; el afiliado sigue contando en totales. `03_limpieza.sql` normaliza las mismas fechas en la base.
- **Evidencia:** evidence/07-fechas.txt

## Incidente 8
- **Síntoma:** el extracto de Caja Oriente trae otras columnas, separador `;` y documentos de 12 dígitos.
- **Diagnóstico:** `id_afiliado` viene con ceros a la izquierda y `situacion` es VIGENTE o RETIRADO; al quitar los ceros y comparar con EST_AFI aparecen 10 documentos que no existen y 15 con estado distinto.
- **Comandos:** `head -3 data/extracto_caja_oriente.csv`, `awk -F';' 'NR>1{print length($1), $3}' data/extracto_caja_oriente.csv | sort | uniq -c`, `cut -d';' -f1 data/extracto_caja_oriente.csv | sed 's/^0*//'`, `grep -c CRUCE_NO_COINCIDE output/excepciones.csv`
- **Solución:** el cierre lee el extracto con su propio separador, quita los ceros, traduce VIGENTE=A y RETIRADO=I y reporta 25 `CRUCE_NO_COINCIDE`; `afiliados_activos.csv` conserva sus 7 columnas.
- **Evidencia:** evidence/08-caja-oriente.txt

## Incidente 9
- **Síntoma:** los totales del cierre no cuadran con `control/hoja_control.csv`.
- **Diagnóstico:** el script heredado contaba filas (1520) en vez de documentos distintos, tomaba todo `A` como activo (1225) sin descontar los activos sin empresa y no calculaba inactivos ni excepciones.
- **Comandos:** `tail -n +2 data/AFI_MAE.csv | wc -l`, `cut -d, -f1 data/AFI_MAE.csv | sort -u | wc -l`, `cat control/hoja_control.csv`, `diff` entre la hoja de control y `output/totales.txt`
- **Solución:** `totales.txt` aplica las reglas del diccionario: total_afiliados=1500, activos=1194, inactivos=274 (igual a la hoja de control) y excepciones=104 (líneas de `excepciones.csv`).
- **Evidencia:** evidence/09-totales.txt

## Incidente 10
- **Síntoma:** el cierre solo funciona una vez; la segunda ejecución falla o da otros resultados.
- **Diagnóstico:** el script heredado hacía `mkdir output` sin `-p` (falla con `set -e`), agregaba con `>>` a `totales.txt` y movía `AFI_MAE.csv` a `procesados/`, dejando la siguiente corrida sin entrada.
- **Comandos:** `git show e9b29b3:scripts/cierre.sh | grep -n -E 'mkdir|>> |mv '`, `sha256sum output/*`, `diff /tmp/corrida1.txt /tmp/corrida2.txt`, `./reset.sh`, `git status --short data/`
- **Solución:** `mkdir -p`, salidas escritas en un temporal y copiadas al final, la entrada no se mueve y el orden es determinista (`LC_ALL=C`). Dos corridas seguidas dan archivos idénticos.
- **Evidencia:** evidence/10-repetible.txt
