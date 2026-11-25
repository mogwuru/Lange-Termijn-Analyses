#-------------------------------------------------------------------------------
# 01_data_cleaning_new.R
#
# Nieuwe versie van R/01_data_cleaning.R voor de DUO-bestanden in data_new/raw/.
# Resultaat: data_new/processed/lta_data_new.rds (+ een .csv-kopie).
# Mapstructuur gelijk aan data/: data_new/raw/ (bronbestanden) en
# data_new/processed/ (gegenereerd).
# Het oorspronkelijke script en data/processed/lta_data.rds blijven ongewijzigd.
#
# Eén rij = één schoolvestiging x toetsjaar (2023, 2024, 2025, 2026).
# Selectie: vestigingen in Amsterdam, Rotterdam, Den Haag en Utrecht met een
# schoolweging > 35 (identiek aan het oorspronkelijke script).
#
# Wat is anders dan in 01_data_cleaning.R:
#   - Schooladviezen (04) en referentieniveaus komen uit data_new/raw/ (.xlsx).
#     In deze bestanden wordt alleen nog onderdrukt ("<5") als het TOTAAL van
#     de vestiging kleiner is dan 5; anders staan alle aantallen er exact in,
#     ook de waarden 1-4.
#   - Beide bestanden hebben een totaalkolom (TOTAAL_ADVIES en
#     TOTAAL_REFERENTIENIVEAUS).
#   - VESTIGINGSCODE heeft nu de vorm BRIN + volgnummer ("13YZ00"); het
#     volgnummer (laatste twee tekens) is de oude vestigingscode.
#   - De kolom ADVIES_NIET_MOGELIJK bestaat niet meer.
#   - Er is een extra schooljaar (2025-2026, toetsjaar 2026).
#   - De eindscores van de doorstroomtoets (05) en de schoolweging zitten niet
#     in data_new/raw/ en komen nog uit data/raw/. Voor toetsjaar 2026 zijn er dus
#     geen gegevens over toets (Cito/IEP), DS_N of DS_score.
#
# Draaien vanuit de projectmap:  source("R/01_data_cleaning_new.R")
#-------------------------------------------------------------------------------

library(tidyverse)
library(readODS)
library(readxl)

pad_raw       <- here::here("data", "raw")
pad_new       <- here::here("data_new", "raw")
pad_processed <- here::here("data_new", "processed")
dir.create(pad_processed, showWarnings = FALSE, recursive = TRUE)

grote_steden <- c("AMSTERDAM", "ROTTERDAM", "'S-GRAVENHAGE", "UTRECHT")
min_schoolweging <- 35


# Hulpfuncties -----------------------------------------------------------------

# Oude DUO-csv's (alleen nog voor de eindscores): puntkomma-gescheiden, als tekst.
lees_duo <- function(bestand) {
  read_delim(
    file.path(pad_raw, bestand),
    delim = ";",
    col_types = cols(.default = col_character()),
    locale = locale(encoding = "UTF-8")
  )
}

# Nieuwe DUO-bestanden (.xlsx): ook alles als tekst, zodat een eventuele "<5"
# (bij een totaal onder de 5) niet stilzwijgend verdwijnt.
lees_duo_xlsx <- function(bestand) {
  read_excel(file.path(pad_new, bestand), col_types = "text")
}

# DUO-getallen gebruiken een decimale komma; "<5" (onderdrukt) wordt NA.
duo_getal <- function(x) {
  parse_double(na_if(x, "<5"), locale = locale(decimal_mark = ","))
}

# Nieuwe vestigingscode "13YZ00" -> 0 (volgnummer)
vestiging_nr <- function(x) as.integer(str_sub(x, -2, -1))


# 1. Schoolweging (Inspectie) --------------------------------------------------
# Ongewijzigd ten opzichte van 01_data_cleaning.R.

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
# Plaatsnaam komt, net als in het oorspronkelijke script, uit het adviesbestand
# van 2024-2025 (nu de nieuwe versie uit data_new/raw/).

scholen <- lees_duo_xlsx("04.-leerlingen-bo-sbo-schooladviezen-2024-2025.xlsx") |>
  filter(PLAATSNAAM %in% grote_steden) |>
  transmute(
    Brin = INSTELLINGSCODE,
    v_code = vestiging_nr(VESTIGINGSCODE),
    PLAATSNAAM
  ) |>
  left_join(schoolweging, by = c("Brin", "v_code")) |>
  filter(schoolweging > min_schoolweging)


# 3. Conditie: RF-scholen versus de rest --------------------------------------
# Ongewijzigd. Bloemhof gaat in 2025 op in de Bloementuin en telt niet apart mee.

rf_vestigingen <- read_ods(file.path(pad_raw, "Doorstroom_duo.ods")) |>
  as_tibble() |>
  filter(School != "Bloemhof") |>
  transmute(
    v_code = as.integer(str_sub(Brin, -2, -1)), # laatste twee tekens = vestiging
    Brin   = str_sub(Brin, 1, -3),              # eerste vier tekens  = BRIN
    conditie = "RF"
  ) |>
  distinct()


# 4. Schooladviezen (DUO, data_new), per toetsjaar ----------------------------
# Toetsjaar = het kalenderjaar waarin het schooljaar eindigt.

adviesbestanden <- c(
  "2023" = "04.-leerlingen-bo-sbo-schooladviezen-2022-2023.xlsx",
  "2024" = "04.-leerlingen-bo-sbo-schooladviezen-2023-2024.xlsx",
  "2025" = "04.-leerlingen-bo-sbo-schooladviezen-2024-2025.xlsx",
  "2026" = "04.-leerlingen-bo-sbo-schooladviezen-2025-2026.xlsx"
)

adviezen <- adviesbestanden |>
  imap(\(bestand, jaar) {
    lees_duo_xlsx(bestand) |>
      select(Brin = INSTELLINGSCODE, v_code = VESTIGINGSCODE,
             INSTELLINGSNAAM_VESTIGING, VSO:VWO, TOTAAL_ADVIES) |>
      mutate(v_code = vestiging_nr(v_code),
             Toetsjaar = as.integer(jaar),
             .after = v_code)
  }) |>
  list_rbind()


# 5. Eindscores doorstroomtoets (DUO, data/raw) --------------------------------
# Ongewijzigd: deze bestanden zitten niet in data_new/raw/. Alleen Cito (LIB; in
# 2022-2023 "CET") en IEP. Geen gegevens voor toetsjaar 2026.

eindscorebestanden <- c(
  "05.-gemiddelde-eindscores-bo-sbo-2022-2023.csv",
  "05.-gemiddelde-eindscores-bo-sbo-2023-2024.csv",
  "05.-gemiddelde-eindscores-bo-sbo-2024-2025.csv"
)

eindscores <- eindscorebestanden |>
  map(\(bestand) {
    lees_duo(bestand) |>
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


# 6. Referentieniveaus rekenen (DUO, data_new) ---------------------------------
# Aantallen per niveau (<1F, 1F, 1S) plus het totaal. Blijven tekst, omdat
# vestigingen met een totaal onder de 5 nog "<5" bevatten.

referentiebestanden <- c(
  "2023" = "leerlingen-bo-referentieniveaus-2022-2023.xlsx",
  "2024" = "leerlingen-bo-referentieniveaus-2023-2024.xlsx",
  "2025" = "leerlingen-bo-referentieniveaus-2024-2025.xlsx",
  "2026" = "leerlingen-bo-referentieniveaus-2025-2026.xlsx"
)

referentieniveaus <- referentiebestanden |>
  imap(\(bestand, jaar) {
    lees_duo_xlsx(bestand) |>
      transmute(
        Brin = INSTELLINGSCODE,
        v_code = vestiging_nr(VESTIGINGSCODE),
        Toetsjaar = as.integer(jaar),
        NAAM_REF = INSTELLINGSNAAM_VESTIGING,
        L_1F = REKENEN_LAGER1F,
        `1F` = REKENEN_1F,
        `1S` = REKENEN_1S,
        REF_TOTAAL = TOTAAL_REFERENTIENIVEAUS
      )
  }) |>
  list_rbind()


# 7. Samenvoegen ---------------------------------------------------------------
# Verschil met het oorspronkelijke script: de rijen (vestiging x toetsjaar)
# komen uit adviezen OF referentieniveaus (full join). In de oude bestanden
# stond een vestiging zonder adviezen nog als rij met alleen nullen in het
# adviesbestand; in de nieuwe bestanden ontbreekt zo'n rij. Zonder full join
# zouden zes vestiging x 2023-rijen met wel referentieniveaus en een
# doorstroomtoets wegvallen (13LW, 13TA, 16UW, 19MP, 19TA, 31JX).

lta_data_new <- scholen |>
  inner_join(
    full_join(adviezen, referentieniveaus, by = c("Brin", "v_code", "Toetsjaar")),
    by = c("Brin", "v_code")
  ) |>
  mutate(INSTELLINGSNAAM_VESTIGING = coalesce(INSTELLINGSNAAM_VESTIGING, NAAM_REF),
         advies_aanwezig = !is.na(TOTAAL_ADVIES)) |>
  select(-NAAM_REF) |>
  left_join(rf_vestigingen, by = c("Brin", "v_code")) |>
  mutate(conditie = replace_na(conditie, "Rest")) |>
  relocate(conditie, .after = PLAATSNAAM) |>
  left_join(eindscores, by = c("Brin", "v_code", "Toetsjaar")) |>
  relocate(Toets, DS_N, DS_score, .before = L_1F) |>
  arrange(Brin, v_code, Toetsjaar)


# 8. Controles -----------------------------------------------------------------

som_tekst <- function(...) {
  m <- sapply(list(...), \(x) suppressWarnings(as.numeric(x)))
  rowSums(matrix(m, ncol = length(list(...))))
}

stopifnot(
  "Dubbele rijen per vestiging x toetsjaar" =
    !anyDuplicated(select(lta_data_new, Brin, v_code, Toetsjaar)),
  "Onverwachte waarden in conditie" =
    all(lta_data_new$conditie %in% c("RF", "Rest")),
  # Waar niets onderdrukt is, moeten de categorieën optellen tot het totaal
  "Referentieniveaus tellen niet op tot TOTAAL_REFERENTIENIVEAUS" =
    with(lta_data_new, {
      s <- som_tekst(L_1F, `1F`, `1S`); t <- suppressWarnings(as.numeric(REF_TOTAAL))
      all(is.na(s) | is.na(t) | s == t)
    }),
  "Adviezen tellen niet op tot TOTAAL_ADVIES" =
    with(lta_data_new, {
      s <- som_tekst(VSO, PRO, VMBO_B, VMBO_B_K, VMBO_K, VMBO_K_GT, VMBO_GT,
                     VMBO_GT_HAVO, HAVO, HAVO_VWO, VWO)
      t <- suppressWarnings(as.numeric(TOTAAL_ADVIES))
      all(is.na(s) | is.na(t) | s == t)
    })
)

lta_data_new |>
  count(conditie, Toetsjaar, heeft_toets = !is.na(DS_N)) |>
  print()


# 9. Opslaan -------------------------------------------------------------------

saveRDS(lta_data_new, file.path(pad_processed, "lta_data_new.rds"))
write_csv(lta_data_new, file.path(pad_processed, "lta_data_new.csv"), na = "")

message("Opgeslagen: data_new/processed/lta_data_new.rds (", nrow(lta_data_new), " rijen)")
