#-------------------------------------------------------------------------------
# run_all_new.R
#
# Draait de analyses opnieuw met de nieuwe DUO-bestanden in data_new/raw/.
# De oorspronkelijke pijplijn (run_all.R) en de bestaande scripts blijven
# ongewijzigd.
#
#   1. data_new/raw/ + data/raw/ -> R/01_data_cleaning_new.R -> data_new/processed/lta_data_new.rds
#   2. data_new/processed/       -> LTA_analyses_nomod_new.qmd      -> .html
#                            -> LTA_adviezen_missings_new.qmd   -> .html
#                            -> LTA_analyses_new.qmd            -> .html (permutaties: enkele minuten)
#                            -> LTA_vergelijking_oud_nieuw.qmd  -> .html (gebruikt ook data/processed/lta_data.rds)
#
# Vereist: R (>= 4.1), Quarto en de pakketten uit R/00_packages.R, plus readxl
# (onderdeel van de tidyverse-installatie).
#-------------------------------------------------------------------------------

source(here::here("R", "01_data_cleaning_new.R"), local = new.env())

# De vergelijking heeft ook de oude dataset nodig
if (!file.exists(here::here("data", "processed", "lta_data.rds"))) {
  source(here::here("R", "01_data_cleaning.R"), local = new.env())
}

for (rapport in c("LTA_analyses_nomod_new.qmd",
                  "LTA_adviezen_missings_new.qmd",
                  "LTA_analyses_new.qmd",
                  "LTA_vergelijking_oud_nieuw.qmd")) {
  quarto::quarto_render(here::here(rapport))
}
