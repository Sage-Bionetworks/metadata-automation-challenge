library(tidyverse)
source("/R/scoring.R")

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  submission_file <- args[1]
  goldstandard_file <- args[2]
  results <- args[3]
  dataset_name <- args[4]
  
  submission_data <- jsonlite::read_json(submission_file)

  anno_data <- jsonlite::read_json(goldstandard_file)
  
  message(glue::glue("Scoring annotation submitted for '{dset_name}' dataset",
                     dset_name = dataset_name))
  
  suppressWarnings(
    score = get_overall_score(submission_data, anno_data)
  )
  result_list = list()
  key = paste0(dataset_name, "_score")
  result_list[[key]] = score
  result_list[['prediction_file_status']] = "SCORED"

  export_json <- toJSON(result_list, auto_unbox = TRUE, pretty=T)
  write(export_json, results)
}

main()

