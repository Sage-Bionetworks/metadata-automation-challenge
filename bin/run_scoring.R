library(tidyverse)
source("/scoring.R")

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  function_arg <- args[1]
  submission_file <- args[2]
  goldstandard_file <- args[3]
  if (function_arg == "score-submission") {
    score_submission(submission_file, goldstandard_file)
  } else {
    results <- args[4]
    dataset_name <- args[5]
    score_submission_tool(submission_file, goldstandard_file,
                          results, dataset_name)
  }
}

# Scoring function submission used by CWL tool
score_submission_tool <- function() {
  submission_data <- jsonlite::read_json(submission_file)

  anno_data <- jsonlite::read_json(goldstandard_file)
  
  message(glue::glue("Scoring annotation submitted for '{dset_name}' dataset",
                     dset_name = dataset_name))
  
  
  score = suppressWarnings(get_overall_score(submission_data, anno_data))
  result_list = list()
  key = paste0(dataset_name, "_score")
  result_list[[key]] = score
  result_list[['prediction_file_status']] = "SCORED"

  export_json <- jsonlite::toJSON(result_list, auto_unbox = TRUE, pretty=T)
  write(export_json, results)
}

# Score submission used by participants
score_submission <- function(submission_file, goldstandard_file) {
  submission_data <- jsonlite::read_json(submission_file)
  anno_data <- jsonlite::read_json(goldstandard_file)
  score = suppressWarnings(get_overall_score(submission_data, anno_data))
  print(score)
}
main()

