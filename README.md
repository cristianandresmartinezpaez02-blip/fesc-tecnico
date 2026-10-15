# Terminal Rescue — <nombre de la pareja>

## Descripción

Sistema de cierre mensual de afiliados de una Caja de Compensación Familiar. A partir de los archivos del sistema legacy genera el archivo de afiliados activos que usa Subsidios, reporta las excepciones de calidad de datos para Auditoría, cuadra los totales con la hoja de control de Operaciones y expone una API de consulta de afiliados. Este repositorio contiene el entorno reparado: los servicios levantan, la API responde y el cierre es repetible.

## Integrantes

- <NOMBRE 1>
- <NOMBRE 2>

## Requisitos

- Docker Engine 24 o superior con el plugin Docker Compose v2 (`docker compose`).
- Bash, `awk`, `grep`, `sort`, `uniq` y `sha256sum` (cualquier Linux; en Windows, Git Bash o WSL).
- Python 3.8+ solo para ejecutar `./validator`.
- El puerto 8081 libre en la máquina.

## Instalación y ejecución

Desde una copia limpia del repositorio, en este orden:

```bash
cp .env.example .env            # crea la configuración local (no se sube a Git)
docker compose up -d --build    # levanta cierre-db, cierre-api y cierre-worker
docker compose ps               # los tres servicios deben estar en running
./run.sh                        # ejecuta el cierre y genera output/
```

Para volver al estado inicial y comprobar que todo se reconstruye desde cero:

```bash
./reset.sh
./run.sh
./run.sh
```

## Configuración

Todas las variables están en `.env.example`; se copian a `.env`, que está en `.gitignore`. Las contraseñas solo viven en `.env`: el código las lee de variables de entorno.

| Variable | Para qué sirve | Ejemplo |
|---|---|---|
| `POSTGRES_DB` | Nombre de la base que crea el contenedor cierre-db al iniciar | `cierre` |
| `POSTGRES_USER` | Usuario dueño de la base en cierre-db | `cierre` |
| `POSTGRES_PASSWORD` | Contraseña de ese usuario (definirla en `.env`) | `cambiar-clave` |
| `DATABASE_HOST` | Host al que se conectan cierre-api y cierre-worker; es el nombre del servicio de Compose, no `localhost` | `cierre-db` |
| `DATABASE_PORT` | Puerto de PostgreSQL dentro de la red de Docker | `5432` |
| `DATABASE_NAME` | Base a la que se conectan la API y el worker; igual a `POSTGRES_DB` | `cierre` |
| `DATABASE_USER` | Usuario de conexión de la API y el worker; igual a `POSTGRES_USER` | `cierre` |
| `DATABASE_PASSWORD` | Contraseña de conexión; igual a `POSTGRES_PASSWORD` | `cambiar-clave` |
| `API_PORT` | Puerto del equipo anfitrión donde se publica cierre-api | `8081` |
| `WORKER_INTERVAL_SECONDS` | Cada cuántos segundos concilia cierre-worker; debe ser un entero sin unidad | `30` |

## Arquitectura

El entorno tiene tres servicios definidos en `docker-compose.yml` que se comunican por la red interna de Docker Compose usando el nombre de cada servicio:

- **cierre-db**: PostgreSQL 16. Al crearse ejecuta `db/init/`: crea las tablas (`01_schema.sql`), carga los CSV de `data/` (`02_load.sql`) y limpia los datos (`03_limpieza.sql`: borra duplicados conservando la primera aparición y normaliza fechas). Tiene un healthcheck con `pg_isready`.
- **cierre-api**: servicio HTTP en Python publicado en el puerto 8081. Consulta `afi_mae` y `empresa` en cierre-db y responde `GET /afiliados/{documento}`.
- **cierre-worker**: proceso en Python que cada `WORKER_INTERVAL_SECONDS` segundos concilia en cierre-db el número de registros contra documentos distintos y lo escribe en su log.

cierre-api y cierre-worker esperan a que cierre-db esté sana (`depends_on: condition: service_healthy`). El cierre (`run.sh` → `scripts/cierre.sh`) corre en el anfitrión: lee los CSV de `data/` y los logs de `logs/`, y escribe en `output/`. Si cierre-db está arriba, `run.sh` reaplica la limpieza de la base con `psql` (es idempotente).

## Uso

Consulta de un afiliado:

```bash
curl http://localhost:8081/afiliados/1098765432
# {"documento": "1098765432", "nombre": "JUAN CARLOS PEREZ GOMEZ", "estado": "ACTIVO", "empresa": "EMPRESA ABC"}
curl -i http://localhost:8081/afiliados/0000000001   # documento inexistente -> 404
```

`GET /afiliados/{documento}` devuelve `documento`, `nombre`, `estado` (`ACTIVO`, `INACTIVO` o `INVALIDO` si el código de estado no es válido) y `empresa` (vacía si el afiliado no tiene empresa válida).

`./run.sh` genera en `output/`:

| Archivo | Contenido |
|---|---|
| `afiliados_activos.csv` | `documento,nombre,estado,cod_empresa,empresa,beneficiarios,ultimo_aporte`, un registro por afiliado activo con empresa válida; `ultimo_aporte` en `YYYY-MM` |
| `excepciones.csv` | `documento,tipo,detalle` con DUPLICADO, SIN_EMPRESA, BENEFICIARIO_HUERFANO, CODIGO_INVALIDO, FECHA_INVALIDA y CRUCE_NO_COINCIDE |
| `totales.txt` | `total_afiliados`, `activos`, `inactivos` y `excepciones` en formato `clave=valor` |
| `top_error.txt` | `codigo_error` y `ocurrencias` del código `CIE-####` más frecuente en `logs/` |

## Pruebas

Con el entorno arriba, `./validator check` ejecuta las pruebas públicas del contrato (servicios, API, salidas, totales y repetibilidad) y `./validator entregables` revisa los documentos. Comprobaciones manuales:

```bash
docker compose ps                                    # cierre-db, cierre-api y cierre-worker en running
curl -s http://localhost:8081/afiliados/1098765432   # 200 con los datos del afiliado
./run.sh && sha256sum output/* > /tmp/a && ./run.sh && sha256sum output/* | diff /tmp/a -   # sin diferencias
cat output/totales.txt control/hoja_control.csv      # total_afiliados, activos e inactivos iguales
```

## Documentación

- [incident-report.md](incident-report.md): síntoma, diagnóstico, comandos y solución de los 10 incidentes.
- [evidence/](evidence/): salida de terminal que demuestra cada arreglo (un archivo por incidente).
- [AI_USAGE.md](AI_USAGE.md): cómo usamos la inteligencia artificial y qué corregimos.
- [docs/diccionario.md](docs/diccionario.md): diccionario de datos y reglas del cierre.

## Qué resolvimos

Corregimos la configuración que tumbaba al worker (intervalo `30s` en vez de `30`) y el host de la base (`cierre-database` en vez de `cierre-db`). Arreglamos el error 500 de la API cuando el segundo nombre está vacío. Reescribimos el cierre: ahora lee `data/`, aplica las reglas del diccionario (duplicados, empresa, beneficiarios, estados, fechas y cruce con Caja Oriente), cuenta el error más frecuente de los logs, cuadra los totales con la hoja de control y produce salidas idénticas cada vez que se ejecuta. La base se limpia de duplicados al crearse.

## Limitaciones y pendientes

- Las fechas inválidas se reportan pero se dejan tal cual en la base; corregirlas requiere el dato real de Operaciones.
- Los afiliados sin empresa, los beneficiarios huérfanos y los códigos de estado inválidos se reportan como excepción pero no se corrigen, porque falta información en el origen.
- La API devuelve `INVALIDO` para estados distintos de A e I; el contrato no define ese caso.
