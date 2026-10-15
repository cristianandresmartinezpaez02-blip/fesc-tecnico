# Uso de inteligencia artificial

## Uso 1
- Herramienta: Claude Code (modelo Claude Opus 5.5) en VS Code
- Para qué se usó: diagnosticar por qué `GET /afiliados/{documento}` respondía 500
- Prompt principal (resumido): "La consulta del afiliado responde 500, diagnostica desde la terminal con logs, grep y awk sin adivinar"
- Qué produjo: intentó cruzar los documentos de los 700 errores CIE-5003 de `api.log` con `AFI_MAE.csv` para encontrar un patrón
- Qué modificó o corrigió el equipo: el cruce dio cero coincidencias porque los documentos del log son de otro mes; cambiamos el enfoque a leer el código de `app.py` y contar los NOM2 vacíos (588), y confirmamos la causa comparando la respuesta esperada con las huellas de `.validator.json`

## Uso 2
- Herramienta: Claude Code (modelo Claude Opus 5.5) en VS Code
- Para qué se usó: reescribir `scripts/cierre.sh` aplicando las reglas de `docs/diccionario.md`
- Prompt principal (resumido): "Genera afiliados_activos.csv, excepciones.csv, totales.txt y top_error.txt con las reglas del diccionario, repetible y solo con bash y utilidades estándar"
- Qué produjo: un script en bash con un programa awk que procesa los cinco CSV y cuenta los códigos CIE de los logs
- Qué modificó o corrigió el equipo: probamos el awk en modo POSIX estricto (`gawk --posix`) porque el servidor Linux puede usar mawk; salió un aviso de un parámetro `doc` que tapaba una variable global y lo renombramos a `documento`; verificamos que las salidas fueran idénticas con ambos awk

## Uso 3
- Herramienta: Claude Code (modelo Claude Opus 5.5) en VS Code
- Para qué se usó: generar los archivos de `evidence/` con la salida real de los comandos de diagnóstico
- Prompt principal (resumido): "Guarda la salida de terminal que demuestra cada arreglo en evidence/NN-nombre.txt"
- Qué produjo: scripts de una línea que ejecutan cada comando y guardan comando y salida en el archivo del incidente
- Qué modificó o corrigió el equipo: la evidencia del incidente 2 buscaba CIE-2210 en `api.log`, donde hay cero apariciones; la cambiamos a `worker.log` y `database.log`. También quitamos de la evidencia 3 una frase sobre los permisos del ZIP que no habíamos comprobado

## Uso 4
- Herramienta: Claude Code (modelo Claude Opus 5.5) en VS Code
- Para qué se usó: organizar el historial de Git con un commit por incidente
- Prompt principal (resumido): "Haz un commit por incidente con un mensaje descriptivo en español"
- Qué produjo: los commits de los incidentes 1 y 2, pero el primero incluía los dos cambios de `.env.example` (intervalo y host)
- Qué modificó o corrigió el equipo: deshicimos esos dos commits y los separamos para que cada uno tenga solo la línea de su incidente, así el historial explica qué arregló cada cambio
