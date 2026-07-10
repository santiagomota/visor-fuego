# visor-fuego

Visor web desarrollado con **Quarto**, **R** y **Leaflet** para el seguimiento operativo del peligro y la actividad de incendios forestales en España.

## Versión actual

**v0.6.4 — publicación AEMET y workflow corregido**

## Fuentes de información

El visor integra las siguientes fuentes:

- **AEMET**: mapas de peligro meteorológico previsto para Península, Baleares y Canarias.
- **NASA FIRMS**: detecciones térmicas recientes y agrupación de alertas.
- **Copernicus / EFFIS**: áreas quemadas utilizadas como capa contextual.
- **Eurostat / GISCO**: límites administrativos de comunidades autónomas y provincias.

## Funcionalidades

- Visualización de capas AEMET por ámbito geográfico y horizonte temporal.
- Consulta de detecciones térmicas recientes de NASA FIRMS.
- Generación de alertas y resúmenes territoriales.
- Visualización contextual de áreas quemadas de EFFIS.
- Resumen operativo, informe y evolución histórica.
- Actualización y publicación automáticas mediante GitHub Actions.
- Validación de los recursos publicados antes de actualizar GitHub Pages.

## Estructura principal

```text
visor-fuego/
├── .github/workflows/       # Automatización de actualización y publicación
├── R/                       # Funciones compartidas
├── assets/                  # Recursos web publicables
│   ├── aemet/
│   ├── effis_ba/
│   └── summary/
├── data/
│   ├── raw/                 # Descargas temporales, no versionadas
│   └── processed/           # Datos procesados y publicables
├── docs/                    # Sitio HTML generado para GitHub Pages
├── scripts/                 # Descarga, procesado, validación y pipeline
├── index.qmd                # Visor principal
├── summary.qmd              # Resumen operativo
├── report.qmd               # Informe
├── history.qmd              # Evolución histórica
├── copernicus.qmd           # Información y capas Copernicus
├── _quarto.yml              # Configuración del sitio
├── styles.css               # Estilos globales
├── .Renviron.example        # Ejemplo de configuración
├── README.md
└── CHANGELOG.md
```

## Requisitos

- R
- Quarto
- Paquetes de R definidos por el proyecto
- Clave de NASA FIRMS para descargar datos recientes

La clave de FIRMS debe definirse mediante la variable:

```text
FIRMS_MAP_KEY
```

Las variables operativas pueden configurarse en un fichero local `.Renviron`. El repositorio incluye `.Renviron.example` como plantilla.

## Configuración local

Copia el fichero de ejemplo:

```bash
cp .Renviron.example .Renviron
```

Edita `.Renviron` y añade, como mínimo, tu clave FIRMS:

```text
FIRMS_MAP_KEY=tu_clave
```

El fichero `.Renviron` contiene configuración local y no debe publicarse en el repositorio.

## Ejecución local

El pipeline canónico del proyecto es:

```bash
Rscript scripts/99_run_all.R
```

Después se genera el sitio:

```bash
quarto render --execute
```

Finalmente se validan los recursos publicados:

```bash
Rscript scripts/11_check_published_assets.R
```

Secuencia completa:

```bash
Rscript scripts/99_run_all.R
quarto render --execute
Rscript scripts/11_check_published_assets.R
```

## Publicación

GitHub Actions realiza automáticamente las siguientes operaciones:

1. Configura el entorno de ejecución.
2. Descarga y procesa las fuentes de datos.
3. Ejecuta `scripts/99_run_all.R`.
4. Renderiza el sitio Quarto en `docs/`.
5. Comprueba los recursos mediante `scripts/11_check_published_assets.R`.
6. Actualiza únicamente los ficheros reproducibles de:
   - `data/processed/`
   - `assets/`
   - `docs/`
7. Realiza un commit solamente cuando existen cambios.
8. Publica el resultado mediante GitHub Pages.

Las descargas temporales de `data/raw/` permanecen excluidas del control de versiones.

## Comportamiento de las capas

### AEMET

Los PNG de AEMET se declaran como recursos del proyecto Quarto y se copian durante el render a:

```text
docs/assets/aemet/
```

La validación posterior comprueba que las imágenes referenciadas por el visor estén realmente disponibles dentro de `docs/`.

### NASA FIRMS

El resumen operativo se genera antes que las alertas y el histórico para que los recuentos y agregados territoriales sean coherentes en todas las páginas.

### EFFIS

La geometría de áreas quemadas:

- se filtra y simplifica para uso web;
- se publica en una única copia dentro de `assets/effis_ba/`;
- se carga bajo demanda desde JavaScript;
- no se incrusta directamente en `docs/index.html`.

La configuración predeterminada utiliza una ventana reciente, una superficie mínima y simplificación geométrica para limitar el tamaño del recurso publicado.

## Validación

El script:

```bash
Rscript scripts/11_check_published_assets.R
```

comprueba, entre otros elementos:

- páginas HTML esperadas;
- imágenes AEMET publicadas;
- GeoJSON de EFFIS;
- recursos referenciados dentro de `docs/`;
- tamaño razonable del HTML principal.

## Estado de la versión v0.6.4

Principales correcciones:

- Corregido el commit automático del workflow.
- `data/raw/` continúa ignorado y no se intenta añadir al commit.
- `.Renviron.example` queda alineado con la configuración operativa del workflow.
- Los recursos AEMET se publican correctamente dentro de `docs/`.
- `scripts/99_run_all.R` es el único pipeline canónico.
- EFFIS se carga bajo demanda y se evita duplicar el GeoJSON.
- Se valida la publicación de los recursos AEMET y EFFIS.
- Se corrige la numeración del horizonte AEMET en la página de resumen.

## Licencia

Este proyecto se distribuye bajo licencia MIT.