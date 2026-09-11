#-------------------------------------------------------------------------------
# 00_packages.R
#
# Installeert de R-pakketten die nodig zijn voor de datacleaning en de
# analyses. Eenmalig draaien vanuit de projectmap:  source("R/00_packages.R")
#
# Voor exact dezelfde pakketversies: zie de sectie "renv" in README.md.
#-------------------------------------------------------------------------------

pakketten <- c(
  # datacleaning
  "tidyverse", "readODS", "here",
  # analyses
  "ordinal", "lme4", "broom", "broom.mixed", "knitr", "conflicted",
  # renderen van het Quarto-rapport
  "rmarkdown", "quarto"
)

ontbrekend <- setdiff(pakketten, rownames(installed.packages()))

if (length(ontbrekend) > 0) {
  message("Installeren: ", paste(ontbrekend, collapse = ", "))
  install.packages(ontbrekend)
} else {
  message("Alle benodigde pakketten zijn al geïnstalleerd.")
}
