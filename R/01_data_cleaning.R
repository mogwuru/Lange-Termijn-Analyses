#-------------------------------------------------------------------------------
# 01_data_cleaning.R
#
# Bouwt de analysedataset voor LTA_analyses.qmd uit de ruwe open data in
# data/raw/. Resultaat: data/processed/lta_data.rds (+ een .csv-kopie).
#
# Eén rij = één schoolvestiging x toetsjaar (2023, 2024, 2025).
# Selectie: vestigingen in Amsterdam, Rotterdam, Den Haag en Utrecht met een
# schoolweging > 35.
#
# Bronnen (zie README.md):
#   - DUO: schooladviezen (04), eindscores doorstroomtoets (05) en
#     referentieniveaus (10), schooljaren 2022-2023 t/m 2024-2025
#   - Inspectie van het Onderwijs: schoolweging (driejaarsgemiddelde)
#   - Doorstroom_duo.ods: lijst van scholen die deelnemen aan RF
#
# Draaien vanuit de projectmap:  source("R/01_data_cleaning.R")
#-------------------------------------------------------------------------------

library(tidyverse)
library(readODS)

pad_raw       <- here::here("data", "raw")
pad_processed <- here::here("data", "processed")
dir.create(pad_processed, showWarnings = FALSE, recursive = TRUE)

grote_steden <- c("AMSTERDAM", "ROTTERDAM", "'S-GRAVENHAGE", "UTRECHT")
min_schoolweging <- 35


# Hulpfuncties -----------------------------------------------------------------

# DUO-bestanden: puntkomma-gescheiden. Alles eerst als tekst inlezen, zodat
# onderdrukte waarden ("<5") en voorloopnullen niet stilzwijgend veranderen.
lees_duo <- function(bestand) {
  read_delim(
    file.path(pad_raw, bestand),
    delim = ";",
    col_types = cols(.default = col_character()),
    locale = locale(encoding = "UTF-8")
  )
}

# DUO-getallen gebruiken een decimale komma; "<5" (onderdrukt) wordt NA.
duo_getal <- function(x) {
  parse_double(na_if(x, "<5"), locale = locale(decimal_mark = ","))
}


# 1. Schoolweging (Inspectie) --------------------------------------------------
# OVT heeft de vorm "BRIN|Cx". De koppeling van Cx naar de DUO-vestigingscode
# is overgenomen uit het oorspronkelijke script (C1 = 0, C2 = 1, C3 = 3,
# C4 = 4); overige codes vallen af.

schoolweging <- read_ods(
  file.path(pad_raw, "schoolweging-2022-2023-2024.ods"),
  sheet = "Driejaarsgemiddelde"
) |>
  as_tibble() |>
  mutate(
    Brin = str_extract(OVT, "[^|]+"),
    c_code = str_extract(OVT, "(?<=\\|).*"),
    v_code = case_when(
      c_code == "C1" ~ 0L,
      c_code == "C2" ~ 1L,
      c_code == "C3" ~ 3L,
      c_code == "C4" ~ 4L
    )
  ) |>
  filter(!is.na(v_code)) |>
  select(Brin, v_code,
         schoolweging = `schoolweging 2022/2023, 2023/2024, 2024/2025`)


# 2. Selectie van scholen: vier grote steden, schoolweging > 35 ----------------
# Plaatsnaam komt uit het meest recente DUO-adviesbestand (2024-2025).

scholen <- lees_duo("04-leerlingen-bo-sbo-schooladviezen-2024-2025.csv") |>
  filter(PLAATSNAAM %in% grote_steden) |>
  transmute(
    Brin = INSTELLINGSCODE,
    v_code = as.integer(VESTIGINGSCODE),
    PLAATSNAAM
  ) |>
  left_join(schoolweging, by = c("Brin", "v_code")) |>
  filter(schoolweging > min_schoolweging)


# 3. Conditie: RF-scholen versus de rest --------------------------------------
# Doorstroom_duo.ods bevat per RF-school de BRIN + vestigingscode (bijv.
# "13YZ00"). Bloemhof gaat in 2025 op in de Bloementuin en telt niet apart mee.

rf_vestigingen <- read_ods(file.path(pad_raw, "Doorstroom_duo.ods")) |>
  as_tibble() |>
  filter(School != "Bloemhof") |>
  transmute(
    v_code = as.integer(str_sub(Brin, -2, -1)), # laatste twee tekens = vestiging
    Brin   = str_sub(Brin, 1, -3),              # eerste vier tekens  = BRIN
    conditie = "RF"
  ) |>
  distinct()


# 4. Schooladviezen (DUO), per toetsjaar ---------------------------------------
# Toetsjaar = het kalenderjaar waarin het schooljaar eindigt.

adviesbestanden <- c(
  "2023" = "04-leerlingen-bo-sbo-schooladviezen-2022-2023.csv",
  "2024" = "04-leerlingen-bo-sbo-schooladviezen-2023-2024.csv",
  "2025" = "04-leerlingen-bo-sbo-schooladviezen-2024-2025.csv"
)

adviezen <- adviesbestanden |>
  imap(\(bestand, jaar) {
    lees_duo(bestand) |>
      select(Brin = INSTELLINGSCODE, v_code = VESTIGINGSCODE,
             INSTELLINGSNAAM_VESTIGING, VSO:ADVIES_NIET_MOGELIJK) |>
      mutate(v_code = as.integer(v_code),
             Toetsjaar = as.integer(jaar),
             .after = v_code)
  }) |>
  list_rbind()


# 5. Eindscores doorstroomtoets (DUO) ------------------------------------------
# Alleen Cito (LIB; in 2022-2023 "CET") en IEP. Toetsjaar volgt uit de
# prikdatum. Een onderdrukt aantal ("<5") telt niet als > 0.

eindscorebestanden <- c(
  "05.-gemiddelde-eindscores-bo-sbo-2022-2023.csv",
  "05.-gemiddelde-eindscores-bo-sbo-2023-2024.csv",
  "05.-gemiddelde-eindscores-bo-sbo-2024-2025.csv"
)

eindscores <- eindscorebestanden |>
  map(\(bestand) {
    lees_duo(bestand) |>
      # In 2022-2023 hebben kolommen nog een andere naam (Cito heette toen CET)
      rename(any_of(c(
        PRIKDATUM  = "PRIKDATUM_SCORES",
        LIB_AANTAL = "CET_AANTAL",
        LIB_GEM    = "CET_GEM"
      ))) |>
      transmute(
        Brin = INSTELLINGSCODE,
        v_code = as.integer(VESTIGINGSCODE),
        Toetsjaar = as.integer(str_sub(PRIKDATUM, 1, 4)), # JJJJMMDD -> JJJJ
        across(c(LIB_AANTAL, LIB_GEM, IEP_AANTAL, IEP_GEM), duo_getal)
      )
  }) |>
  list_rbind() |>
  filter(LIB_AANTAL > 0 | IEP_AANTAL > 0) |>
  mutate(
    Toets = case_when(
      LIB_AANTAL > 0 ~ "Cito",
      IEP_AANTAL > 0 ~ "IEP"
    ),
    DS_N     = if_else(Toets == "Cito", LIB_AANTAL, IEP_AANTAL),
    DS_score = if_else(Toets == "Cito", LIB_GEM, IEP_GEM)
  ) |>
  select(Brin, v_code, Toetsjaar, Toets, DS_N, DS_score)


# 6. Referentieniveaus rekenen (DUO) -------------------------------------------
# Aantallen leerlingen per niveau (<1F, 1F, 1S). Blijven tekst omdat ze "<5"
# kunnen bevatten; de afhandeling daarvan gebeurt in LTA_analyses.qmd.
# 2F is voor rekenen altijd 0 en wordt niet meegenomen.

referentiebestanden <- c(
  "2023" = "10.-leerlingen-bo-referentieniveaus-2022-2023.csv",
  "2024" = "10.-leerlingen-bo-referentieniveaus-2023-2024.csv",
  "2025" = "10.-leerlingen-bo-referentieniveaus-2024-2025.csv"
)

referentieniveaus <- referentiebestanden |>
  imap(\(bestand, jaar) {
    lees_duo(bestand) |>
      transmute(
        Brin = INSTELLINGSCODE,
        v_code = as.integer(VESTIGINGSCODE),
        Toetsjaar = as.integer(jaar),
        L_1F = REKENEN_LAGER1F,
        `1F` = REKENEN_1F,
        `1S` = REKENEN_1S
      )
  }) |>
  list_rbind()


# 7. Samenvoegen ---------------------------------------------------------------

lta_data <- scholen |>
  left_join(adviezen, by = c("Brin", "v_code")) |>
  left_join(rf_vestigingen, by = c("Brin", "v_code")) |>
  mutate(conditie = replace_na(conditie, "Rest")) |>
  relocate(conditie, .after = PLAATSNAAM) |>
  left_join(eindscores, by = c("Brin", "v_code", "Toetsjaar")) |>
  left_join(referentieniveaus, by = c("Brin", "v_code", "Toetsjaar"))


# 8. Controles -----------------------------------------------------------------

stopifnot(
  "Dubbele rijen per vestiging x toetsjaar" =
    !anyDuplicated(select(lta_data, Brin, v_code, Toetsjaar)),
  "Onverwachte waarden in conditie" =
    all(lta_data$conditie %in% c("RF", "Rest"))
)

lta_data |>
  count(conditie, Toetsjaar, heeft_toets = !is.na(DS_N)) |>
  print()


# 9. Opslaan -------------------------------------------------------------------

saveRDS(lta_data, file.path(pad_processed, "lta_data.rds"))
write_csv(lta_data, file.path(pad_processed, "lta_data.csv"), na = "")

message("Opgeslagen: data/processed/lta_data.rds (", nrow(lta_data), " rijen)")
