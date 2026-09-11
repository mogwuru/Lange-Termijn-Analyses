#-------------------------------------------------------------------------------
# run_all.R
#
# Reproduceert het volledige project vanuit de ruwe data:
#   1. data/raw/            -> R/01_data_cleaning.R -> data/processed/lta_data.rds
#   2. data/processed/      -> LTA_analyses.qmd     -> LTA_analyses.html
#
# Vereist: R (>= 4.1) en Quarto (https://quarto.org). Eenmalig vooraf:
#   source("R/00_packages.R")
#-------------------------------------------------------------------------------

source(here::here("R", "01_data_cleaning.R"), local = new.env())

quarto::quarto_render(here::here("LTA_analyses.qmd"))
