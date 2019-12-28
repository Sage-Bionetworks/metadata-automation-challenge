library(tidyverse)
source("R/scoring.R")

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  dataset_name <- args[1]
  submission_file <- args[2]
  
  path_template <- "/data/Annotated-{dset_name}.json"
  
  submission_data <- jsonlite::read_json(submission_file)

  anno_data <- jsonlite::read_json(
    glue::glue(path_template,
               dset_name = dataset_name)
  )
  
  message(glue::glue("Scoring annotation submitted for '{dset_name}' dataset",
                     dset_name = dataset_name))
  
  suppressWarnings(
    get_overall_score(submission_data, anno_data)
  )
}

main()