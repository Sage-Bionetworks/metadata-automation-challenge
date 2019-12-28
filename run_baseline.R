library(tidyverse)
library(fuzzyjoin)
source("baseline_annotator.R")

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  dataset_name <- args[1]
  message(glue::glue("Annotating input table for '{dset_name}' dataset",
                     dset_name = dataset_name))
  run_annotator(dataset_name)
}

main()