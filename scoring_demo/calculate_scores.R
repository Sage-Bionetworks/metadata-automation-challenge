setwd("scoring_demo/")
source("global.R")

number_of_columns = c(1:length(submission_data$columns))

column_scores = sapply(number_of_columns, function(column) {
  sub_data <- purrr::keep(
    submission_data$columns, ~ .x$columnNumber == column
  ) %>% 
    pluck(1)
  
  anno_data <- purrr::keep(
    submission_annotated$columns, ~ .x$columnNumber == column
  ) %>% 
    pluck(1)
  
  num_res <- length(sub_data$result)
  res_scores <- map(1:num_res, function(r) {
    get_res_score(sub_data, anno_data, r)
  })
  print(get_col_score(res_scores))
})

names(column_scores) = number_of_columns
