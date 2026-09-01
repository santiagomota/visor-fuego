# Visor fuego

Visor web operativo para seguir el peligro meteorológico de incendios, las
detecciones tÃ©rmicas recientes y las áreas quemadas en EspaÃ±a.

**Versión actual:** `v0.6.31`

**Visor publicado:** <https://santiagomota.github.io/visor-fuego/>

El proyecto combina R, Quarto y Leaflet. GitHub Actions actualiza los datos,
construye un snapshot verificable y despliega el sitio en GitHub Pages.

> [!IMPORTANT]
> El visor integra fuentes externas y sirve como apoyo a la consulta. No
> sustituye la información, las alertas ni las instrucciones de los organismos
> oficiales de protección civil y emergencias.

## Contenido del visor

- **Mapa:** peligro AEMET, focos NASA FIRMS, áreas quemadas EFFIS y límites
  administrativos, con navegación temporal y consulta territorial.
- **Resumen:** síntesis de la situación por comunidad autónoma y provincia.
- **Informe:** alertas y lectura operativa de las detecciones recientes.
- **Evolución:** histórico de los principales indicadores del visor.
- **Copernicus:** información específica de las áreas quemadas EFFIS.

El mapa permite recorrer los horizontes de AEMET, reproducir la secuencia
temporal, seleccionar comunidades o provincias y consultar indicadores FIRMS,
EFFIS y AEMET para el territorio elegido.

## Fuentes de datos

| Fuente | Información utilizada | Tratamiento en el proyecto |
| --- | --- | --- |
| [AEMET](https://www.aemet.es/) | Índice de peligro de incendios previsto para Península/Baleares y Canarias | GeoTIFF oficiales, reproyectados a Web Mercator y representados con las seis clases IPIF y su simbología oficial |
| [NASA FIRMS](https://firms.modaps.eosdis.nasa.gov/) | Detecciones tÃ©rmicas VIIRS recientes | Normalización, ventanas de 6, 12, 24 y 48 horas, FRP y agrupación de alertas |
| [Copernicus EFFIS](https://effis.jrc.ec.europa.eu/) | Perámetros y superficies quemadas | Capa contextual de los Últimos 90 días, descargada y simplificada para la web |
| [Eurostat GISCO](https://ec.europa.eu/eurostat/web/gisco/) | Límites NUTS | Comunidades autónomas y provincias para agregación y consulta territorial |

Las fechas de **emisión** y **validez** de AEMET se muestran por separado. El
visor oculta las fechas válidas ya pasadas y evita interpretar una emisión de
ayer válida para hoy como un dato obsoleto.

## Garantías de actualidad y coherencia

Desde `v0.6.28`, cada actualización genera un snapshot inmutable en
`assets/runtime/<build_id>/`. `assets/site-build.json` identifica el build
publicado y registra sus recursos y comprobaciones SHA-256.

El navegador carga los datos operativos en tiempo de ejecución con control de
cachÃ©. El pipeline comprueba, antes y despuÃ©s del despliegue, que el HTML, el
manifiesto y los recursos pertenecen al mismo build. Esto evita que una copia
antigua del HTML vuelva a mostrar datos de una ejecución anterior.

Otras salvaguardas relevantes:

- AEMET debe proporcionar una emisión de hoy o de ayer y una fuente oficial de
  simbología (`ESCALA`, tabla de color, SLD o QML).
- Si FIRMS falla o responde sin detecciones, puede conservarse hasta 72 horas el
  último snapshot válido, marcado como `stale_preserved`, para evitar un falso
  estado de cero focos.
- EFFIS es opcional: una incidencia de esta capa contextual no impide actualizar
  el resto del visor.
- El sitio se renderiza siempre de nuevo (`freeze: false`) y se valida antes de
  publicarse.

## Actualización automática

El workflow [Actualizar visor fuego](.github/workflows/update-dashboard.yml)
mantiene dos horas objetivo diarias en la zona `Europe/Madrid`:

- **04:30**
- **12:30**

GitHub Actions ejecuta además un watchdog ligero cada 20 minutos, a los minutos
`07`, `27` y `47`, entre las 04:00 y las 23:59. El watchdog consulta el
`site-build.json` realmente publicado:

- si Pages ya contiene el build correspondiente a la franja, termina sin
  instalar dependencias ni repetir el pipeline;
- si el build falta, está atrasado o no puede verificarse, ejecuta la
  actualización completa;
- una ejecución manual siempre ejecuta el pipeline completo.

La concurrencia está limitada a una actualización activa y las ejecuciones en
cola no cancelan la que ya está en curso.

## Requisitos

- R y los paquetes declarados en [`DESCRIPTION`](DESCRIPTION).
- [Quarto](https://quarto.org/).
- GDAL/PROJ/GEOS y las bibliotecas del sistema requeridas por `sf` y `terra`.
- Una `MAP_KEY` de NASA FIRMS para descargar detecciones.
- Opcionalmente, una clave de CARTO Basemaps restringida al dominio del visor.

En Ubuntu, el workflow del proyecto sirve como referencia reproducible para las
dependencias del sistema y de R.

## Configuración local

Clona el repositorio y entra en su directorio:

```bash
git clone https://github.com/santiagomota/visor-fuego.git
cd visor-fuego
```

Crea la configuración local a partir de la plantilla:

```bash
cp .Renviron.example .Renviron
```

Edita `.Renviron` y define, como mínimo:

```dotenv
FIRMS_MAP_KEY=tu_clave_firms
CARTO_BASEMAP_KEY=tu_clave_carto
```

`CARTO_BASEMAP_KEY` es opcional; sin ella se utiliza OpenStreetMap. Al tratarse
de un sitio estático, la clave CARTO llega al navegador y debe restringirse al
dominio autorizado. No confirmes `.Renviron` en Git.

El proveedor AEMET configurado por defecto es `classic` y no necesita una clave
de AEMET. El resto de opciones y sus valores recomendados están documentados en
[`.Renviron.example`](.Renviron.example).

## Ejecución local

Ejecuta el pipeline canónico, renderiza el sitio y valida el resultado:

```bash
Rscript scripts/99_run_all.R
quarto render
Rscript scripts/11_check_published_assets.R
```

La salida se genera en `docs/`. Para previsualizarla con recarga automática:

```bash
quarto preview
```

El pipeline realiza, en orden, la descarga y preparación de AEMET y FIRMS, la
actualización opcional de EFFIS, los resúmenes territoriales, las alertas, el
histórico, las validaciones y la creación del manifiesto del build.

## Estructura del repositorio

```text
.
â”œâ”€â”€ R/                 # Funciones del pipeline y del visor
â”œâ”€â”€ scripts/           # Descarga, preparación, validación y orquestación
â”œâ”€â”€ assets/            # Snapshot canónico publicado y recursos runtime
â”œâ”€â”€ data/processed/    # Productos procesados versionados
â”œâ”€â”€ docs/              # Sitio renderizado localmente
â”œâ”€â”€ *.qmd              # Páginas Quarto
â”œâ”€â”€ _quarto.yml        # Configuración del sitio
â””â”€â”€ sw.js              # Control de cachÃ© y actualización del navegador
```

`scripts/99_run_all.R` es el único punto de entrada del pipeline completo. Los
scripts numerados restantes pueden utilizarse para diagnóstico o para ejecutar
una etapa concreta durante el desarrollo.

## Publicación

En **Settings â†’ Pages â†’ Build and deployment**, la fuente debe ser **GitHub
Actions**. El workflow:

1. verifica que el código fuente y la versión sean coherentes;
2. actualiza y valida los datos;
3. renderiza desde cero el sitio en `docs/`;
4. despliega el artefacto directamente en GitHub Pages;
5. comprueba el build servido por la web pública;
6. guarda en Git, como operación independiente, los cambios reproducibles de
   `assets/` y `data/processed/`.

`docs/` no se confirma automáticamente: el artefacto ya desplegado contiene el
render y así se evita guardar en el historial la URL de CARTO con su clave.

Los secretos necesarios en **Settings â†’ Secrets and variables â†’ Actions** son:

- `FIRMS_MAP_KEY`
- `CARTO_BASEMAP_KEY`

## Diagnóstico

- [`assets/site-build.json`](assets/site-build.json): build y fecha que deben
  estar publicados.
- [`assets/aemet/status.json`](assets/aemet/status.json): emisión y estado de
  AEMET.
- [`assets/firms/status.json`](assets/firms/status.json): descarga vigente o
  snapshot FIRMS preservado.
- [`scripts/11_check_published_assets.R`](scripts/11_check_published_assets.R):
  validación integral del sitio renderizado.
- [Historial de Actions](https://github.com/santiagomota/visor-fuego/actions):
  ejecuciones automáticas y manuales.

## Versionado y licencia

El proyecto utiliza versionado semántico. Los cambios de cada versión se
documentan en [`CHANGELOG.md`](CHANGELOG.md) y las versiones publicadas están en
[Releases](https://github.com/santiagomota/visor-fuego/releases).

Código distribuido bajo licencia [MIT](LICENSE).
