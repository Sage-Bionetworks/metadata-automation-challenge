get_score_checks <- function(de_wt=1.0, dec_wt=1.0, top_wt=2.0, vd_wt=.5) {
  score_checks <- tibble::tribble(
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

get_column_data <- function(data, col_num) {
  purrr::keep(data$columns, ~ .$columnNumber == col_num) %>% 
    purrr::flatten()
}

get_result_data <- function(col_data, res_num = 1) {
  col_results <- col_data$results
  purrr::keep(col_results, ~ .$resultNumber == res_num) %>% 
    purrr::flatten()
}

get_de_id <- function(res_data) {
  suppressWarnings(
    if (res_data$result$dataElement$name == "NOMATCH") {
      ""
    } else {
      res_data$result$dataElement$id
    }
  )
}

get_dec_id <- function(res_data) {
  suppressWarnings(
    if (res_data$result$dataElementConcept$name == "NOMATCH") {
      ""
    } else {
      res_data$result$dataElementConcept$id
    }
  )
}

get_dec_concepts <- function(res_data) {
  suppressWarnings(
    if (res_data$result$dataElementConcept$name == "NOMATCH") {
      c()
    } else {
      res_data$result$dataElementConcept$conceptCodes %>%
        purrr::flatten_chr()
    }
  )
}

get_value_domain <- function(res_data) {
  suppressWarnings(
    if (res_data$result$dataElement$name == "NOMATCH") {
      tibble::tibble(observedValue = NA, name = NA, id = NA) %>% 
        dplyr::filter(complete.cases(.))
    } else {
      res_data$result$valueDomain %>% 
        purrr::map(~ list(observedValue = .$observedValue, 
                          value = .$permissibleValue$value, 
                          conceptCode = .$permissibleValue$conceptCode)) %>% 
        purrr::map(~ purrr::discard(., is.null)) %>% 
        purrr::map_df(tibble::as_tibble)
    }
  )
}

find_mismatch_cols <- function(df_a, df_b) {
  names(df_a) %>% 
    purrr::imap(function(n, x) {
      if (any(df_a[[x]] != df_b[[x]])) {
        n
      }
    }) %>% 
    purrr::discard(is.null) %>% 
    purrr::flatten_chr()
}

find_mismatch_rows <- function(df_a, df_b, col_name = "conceptCode") {
  df_a[[col_name]][!(df_a[[col_name]] %in% df_b[[col_name]])]
}

score_concept_overlap <- function(sub_res_data, anno_res_data) {
  sub_c_ids <- get_dec_concepts(sub_res_data)
  anno_c_ids <- get_dec_concepts(anno_res_data)
  jaccard(sub_c_ids, anno_c_ids)
}

score_value_coverage <- function(sub_res_data, anno_res_data) {
  sub_vd <- get_value_domain(sub_res_data)
  anno_vd <- get_value_domain(anno_res_data)
  anno_nonenum <- any(stringr::str_detect(anno_vd$value, "CONFORMING"))
  if (anno_nonenum) {
    check_col <- "value"
  } else {
    check_col <- "conceptCode"
  }
  mismatch_rows <- find_mismatch_rows(sub_vd, anno_vd, check_col)
  if (nrow(anno_vd) & length(mismatch_rows)) {
    1 - (length(mismatch_rows) / nrow(anno_vd))
  } else {
    0
  }
}

get_res_score <- function(sub_col_data,
                          anno_col_data,
                          res_num,
                          score_checks,
                          overlap_thresh = 0.5,
                          coverage_thresh = 0.8) {
  
  sub_res_data <- get_result_data(sub_col_data, res_num)
  suppressWarnings(
    sub_no_match <- sub_res_data$result$dataElement$name == "NOMATCH"
  )
  anno_res_data <- get_result_data(anno_col_data)
  suppressWarnings(
    anno_no_match <- anno_res_data$result$dataElement$name == "NOMATCH"
  )

  metric_3 <- score_concept_overlap(sub_res_data, anno_res_data)
  metric_4 <- 0
  
  suppressWarnings(
    if (sub_no_match & anno_no_match) {
      check_1 <- TRUE
    } else {
      check_1 <- magrittr::equals(
        get_de_id(sub_res_data),
        get_de_id(anno_res_data)
      )
    }
  )
  check_2 <- FALSE
  check_3 <- FALSE
  check_4 <- FALSE
  if (check_1) {
    check_2 <- res_num == 1
    if (!check_2) {
      check_3 <- metric_3 > overlap_thresh
    }
  } else {
    check_3 <- metric_3 > overlap_thresh
    
    if (!check_3) {
      metric_4 <- score_value_coverage(sub_res_data, anno_res_data)
      
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


get_col_score <- function(res_scores, aggregate_by="max") {
  scores = sapply(res_scores, function(x) { sum(x$score, na.rm = T) })
  # Get max of all result scores
  if (aggregate_by == "max") {
    max(scores)
  } else {
    median(scores)
  }
}

get_de_table <- function(col_data, res_num = 1) {
  tibble::as_tibble(col_data$results[[res_num]]$result$dataElement)
}

get_dec_table <- function(col_data, res_num = 1) {
  tibble::as_tibble(col_data$results[[res_num]]$result$dataElementConcept) %>% 
    dplyr::select(-conceptCodes) %>% 
    dplyr::distinct()
}

get_overall_score <- function(sub_data,
                              anno_data,
                              score_checks = get_score_checks(),
                              aggregate_by = "max",
                              overlap_thresh = 0.5,
                              coverage_thresh = 0.8) {
  
  n_columns <- length(sub_data$columns)
  col_scores <- purrr::map(c(1:n_columns), function(col) {
    sub_col_data <- get_column_data(sub_data, col)
    anno_col_data <- get_column_data(anno_data, col)
    n_res <- max(purrr::map_dbl(sub_col_data$results, "resultNumber"))
    
    res_scores <- purrr::map(1:n_res, function(r) {
      get_res_score(
        sub_col_data,
        anno_col_data,
        res_num = r,
        score_checks = score_checks,
        overlap_thresh = overlap_thresh,
        coverage_thresh = coverage_thresh
      )
    })
    get_col_score(res_scores, aggregate_by = aggregate_by)
  }) %>%
    purrr::flatten_dbl()
  sum(col_scores) / length(col_scores)
}


