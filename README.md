# LTA-analyses: referentieniveaus rekenen naar conditie

Reproduceerbare analyse van de rekenreferentieniveaus (<1F / 1F / 1S) aan het einde van de basisschool: RF-scholen vergeleken met overige scholen met een schoolweging > 35 in Amsterdam, Rotterdam, Den Haag en Utrecht, over de toetsjaren 2023–2025.

Auteurs: Mike Ogwuru, Abe Hofman

## Structuur

```
.
├── LTA_analyses.qmd          # Het rapport: cleaning van suppressie, beschrijvende statistiek, ordinale modellen
├── run_all.R                 # Draait de hele pijplijn: ruwe data -> dataset -> rapport
├── R/
│   ├── 00_packages.R         # Installeert de benodigde R-pakketten
│   └── 01_data_cleaning.R    # Bouwt data/processed/lta_data.rds uit data/raw/
├── data/
│   ├── raw/                  # Ruwe bestanden (niet handmatig aanpassen)
│   └── processed/            # Wordt gegenereerd door 01_data_cleaning.R (niet in git)
├── LTA.Rproj
└── README.md
```

## Reproduceren

Benodigd: [R](https://cran.r-project.org) (versie 4.1 of hoger) en [Quarto](https://quarto.org). RStudio of Positron is handig maar niet verplicht.

1. Clone of download deze map en open `LTA.Rproj` (of zet de werkmap op de projectmap).
2. Installeer de pakketten (eenmalig):
   ```r
   source("R/00_packages.R")
   ```
3. Draai de volledige pijplijn:
   ```r
   source("run_all.R")
   ```
   Dit maakt eerst `data/processed/lta_data.rds` en rendert daarna `LTA_analyses.html`.

De stappen kunnen ook los worden gedraaid: `source("R/01_data_cleaning.R")` voor alleen de dataset, of `quarto render LTA_analyses.qmd` in de terminal voor alleen het rapport. Als de dataset nog niet bestaat, wordt het cleaningscript vanuit het rapport automatisch eerst gedraaid.

De permutatietoets (sectie 6.2, 1000 modelfits) duurt enkele minuten. Het resultaat wordt gecachet in `LTA_analyses_cache/`. Verwijder die map om alles opnieuw te berekenen.

### Controlegetallen

Een correcte reproductie geeft onder meer:

| Controle | Waarde |
|---|---|
| Rijen in `lta_data.rds` | 501 (vestiging × toetsjaar) |
| Rijen met een doorstroomtoets (`DS_N` niet leeg) | 467, 159 vestigingen |
| Analysesteekproef na cleaning | 407 rijen, 155 vestigingen (7 RF, 148 Rest) |
| Leerlingen per niveau (<1F / 1F / 1S) | 1556 / 6620 / 4649 |

## Pijplijn

**`R/01_data_cleaning.R`** (tidyverse):

1. Schoolweging (driejaarsgemiddelde) inlezen en koppelen aan BRIN + vestigingscode.
2. Vestigingen selecteren in de vier grote steden met schoolweging > 35.
3. Conditie bepalen: vestigingen uit `Doorstroom_duo.ods` zijn `RF`, alle andere `Rest`.
4. Schooladviezen, eindscores van de doorstroomtoets (Cito of IEP) en rekenreferentieniveaus per toetsjaar koppelen.
5. Controleren (geen dubbele rijen) en opslaan als `data/processed/lta_data.rds` en `.csv`.

**`LTA_analyses.qmd`**: afhandeling van onderdrukte cellen (`<5`) via afleiding uit het totaal, consistentiecontroles, beschrijvende statistiek, cumulatieve link modellen (`ordinal::clm`/`clmm`), drempelspecifieke binomiale GLMM's (`lme4`), een gevoeligheidsanalyse en een permutatietoets op schoolniveau.

## Databronnen (`data/raw/`)

| Bestand | Bron | Inhoud |
|---|---|---|
| `04-leerlingen-bo-sbo-schooladviezen-<schooljaar>.csv` | DUO Open Onderwijsdata | Schooladviezen per vestiging; ook bron voor plaatsnaam en vestigingsnaam |
| `05.-gemiddelde-eindscores-bo-sbo-<schooljaar>.csv` | DUO Open Onderwijsdata | Aantal deelnemers en gemiddelde score per doorstroomtoets |
| `10.-leerlingen-bo-referentieniveaus-<schooljaar>.csv` | DUO Open Onderwijsdata | Aantal leerlingen per referentieniveau |
| `schoolweging-2022-2023-2024.ods` | Inspectie van het Onderwijs | Schoolweging, gemiddelde 2022/2023–2024/2025 (tabblad `Driejaarsgemiddelde`) |
| `Doorstroom_duo.ods` | Eigen overzicht | Scholen die deelnemen aan RF (BRIN + vestigingscode) |

Schooljaren 2022-2023, 2023-2024 en 2024-2025 (toetsjaren 2023, 2024, 2025). DUO-bestanden: [duo.nl/open_onderwijsdata](https://duo.nl/open_onderwijsdata/).

## Pakketversies vastleggen met renv (aanbevolen)

Om te zorgen dat anderen exact dezelfde pakketversies gebruiken, legt de auteur de versies één keer vast:

```r
install.packages("renv")
renv::init()      # kies de optie om de pakketten uit de huidige bibliotheek te gebruiken
renv::snapshot()  # schrijft renv.lock
```

Commit daarna `renv.lock`, `.Rprofile` en `renv/activate.R`. Iemand anders draait dan `renv::restore()` in plaats van `source("R/00_packages.R")`.

## Aandachtspunten

- De koppeling tussen de vestigingscodes van de Inspectie (`C1`, `C2`, …) en die van DUO (`0`, `1`, …) is overgenomen uit het oorspronkelijke script (`C1 = 0`, `C2 = 1`, `C3 = 3`, `C4 = 4`). Vestigingen met DUO-code `2` krijgen daardoor geen schoolweging en vallen buiten de selectie. Controleer deze koppeling als de selectie wordt uitgebreid.
- Een onderdrukt aantal deelnemers (`<5`) bij een doorstroomtoets telt niet mee bij het bepalen van de toets (Cito of IEP).
- Inhoudelijke keuzes en beperkingen van de analyse staan in sectie 8 van het rapport.
