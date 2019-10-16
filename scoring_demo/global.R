library(shiny)
library(listviewer)
library(DT)
library(shinyjs)
library(tibble)
library(purrr)
library(dplyr)

submission_data <- readr::read_file("../scoring/test_rembrandt.json") %>%
  jsonlite::fromJSON(simplifyVector = FALSE)
submission_annotated <- readr::read_file("../scoring/annotated_rembrandt.json") %>%
  jsonlite::fromJSON(simplifyVector = FALSE)

get_score_checks <- function(de_wt=1.0, dec_wt=1.0, top_wt=2.0, vd_wt=.5) {
  score_checks <- tribble(
    ~step, ~check, ~nextIfTrue, ~nextIfFalse, ~pointsIfTrue,
    1L, "Result matches Gold Standard?", 2L, 3L, de_wt,
    2L, "Top Result = Gold Standard?", NA, 3L, top_wt,
    3L, "'Good' DEC Concept Codes Match?", NA, 4L, dec_wt,
    4L, "'Good' VD Coverage?", NA, 5L, vd_wt,
    5L, "[HR] Better Match?", NA, NA, 1
  )
  score_checks
}

jaccard <- function(list_a, list_b) {
  n <- length(intersect(list_a, list_b))
  u <- length(union(list_a, list_b))
  n / u
}

get_dec_concepts <- function(col_data, res_num = 1) {
  col_data$results[[res_num]]$result$dataElementConcept$concepts %>% 
    flatten_chr() %>% 
    unique()
}

get_observed_values <- function(col_data, res_num = 1) {
  col_data$results[[res_num]]$observedValues %>% 
    map(~ list(value = .$value, name = .$concept$name, id = .$concept$id)) %>% 
    map(~ discard(., is.null)) %>% 
    map_df(as_tibble)
}


get_res_score <- function(sub_data, anno_data, res_num, score_checks,
                          overlap_thresh = 0.5,
                          coverage_thresh = 0.8) {
  sub_c_ids <- get_dec_concepts(sub_data, res_num)
  anno_c_ids <- get_dec_concepts(anno_data)
  metric_3 <- jaccard(sub_c_ids, anno_c_ids)
  
  sub_ovs <- get_observed_values(sub_data, res_num)
  anno_ovs <- get_observed_values(anno_data)
  if ("id" %in% names(sub_ovs)) {
    check_col <- "id"
  } else {
    check_col <- "name"
  }
  mismatch_rows <- find_mismatch_rows(sub_ovs, anno_ovs, check_col)
  metric_4 <- 1 - (length(mismatch_rows) / nrow(anno_ovs))
  
  check_1 <- magrittr::equals(
    sub_data$results[[res_num]]$result$dataElementConcept$id,
    anno_data$results[[1]]$result$dataElementConcept$id
  )
  
  check_2 <- NA
  check_3 <- NA
  check_4 <- NA
  if (check_1) {
    check_2 <- res_num == 1
    if (!check_2) {
      check_3 <- metric_3 > overlap_thresh
    } 
  } else {
    check_3 <- metric_3 > overlap_thresh
    
    if (!check_3) {
      check_4 <- metric_4 > coverage_thresh
      
    }
  }
  
  score_1 <- check_1*score_checks$pointsIfTrue[[1]]
  score_2 <- check_2*score_checks$pointsIfTrue[[2]]
  score_3 <- check_3*metric_3*score_checks$pointsIfTrue[[3]]
  score_4 <- check_4*metric_4*score_checks$pointsIfTrue[[4]]
  
  
  list(step = 1:4,
       metric = c(check_1, check_2, metric_3, metric_4),
       status = c(check_1, check_2, check_3, check_4),
       score = c(score_1, score_2, score_3, score_4))
}

# get_col_score <- function(sub_data, anno_data, num_res) {
#   
# }

get_de_table <- function(col_data, res_num = 1) {
  as_tibble(col_data$results[[res_num]]$result$dataElement)
}

get_dec_table <- function(col_data, res_num = 1) {
  as_tibble(col_data$results[[res_num]]$result$dataElementConcept) %>% 
    select(-concepts) %>% 
    distinct()
}

find_mismatch_cols <- function(df_a, df_b) {
  names(df_a) %>% 
    imap(function(n, x) {
      if (any(df_a[[x]] != df_b[[x]])) {
        n
      }
    }) %>% 
    discard(is.null) %>% 
    flatten_chr()
}

find_mismatch_rows <- function(df_a, df_b, col_name = "id") {
  df_a[[col_name]][!(df_a[[col_name]] %in% df_b[[col_name]])]
}