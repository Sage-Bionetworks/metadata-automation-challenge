
get_score_checks <- function(
  de_wt=1.5, 
  dec_wt=1.0, 
  vd_wt=.5,
  top_wt=2.0 
) {
  
  score_checks <- tibble::tribble(
    ~step, ~check, ~metric, ~range, ~weight,
    1L, "DE Match", "DE:ID<sub>res</sub> == DE:ID<sub>gold</sub>", "0, 1", de_wt,
    2L, "DEC Concept Code Overlap", "jaccard(DEC:conceptCodes<sub>res</sub>, DEC:conceptCodes<sub>gold</sub>", "0 - 1", dec_wt,
    3L, "VD Coverage", "Pr(VD:permissibleValue<sub>res</sub>|VD:permissibleValue<sub>gold</sub>", "0 - 1", vd_wt,
    4L, "Result Rank Bonus", "(3 - resultNumber) * mean(steps 1-3)", "0 - 2", top_wt
  )
  
  score_checks
  
}

jaccard <- function(list_a, list_b) {

  n <- length(intersect(list_a, list_b))
  u <- length(union(list_a, list_b))
  
  if (n == 0 & u == 0) {
    1
  } else if (n == 0 | u == 0) {
    0
  } else {
    n / u
  }

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
  

    if (res_data$result$dataElement$name == "NOMATCH") {
      tibble::tibble(observedValue = NA, name = NA, id = NA) %>% 
        dplyr::filter(complete.cases(.))
    } else {
      res_data$result$valueDomain %>% 
        purrr::map(~ list(observedValue = .$observedValue, 
                          value = .$permissibleValue$value, 
                          conceptCode = .$permissibleValue$conceptCode)) %>% 
        purrr::modify_depth(2, ~ ifelse(is.null(.), "", .)) %>%
        purrr::map_df(tibble::as_tibble) %>%
        dplyr::mutate(conceptCode = ifelse(conceptCode == "", NA, conceptCode))
    }

}


find_mismatch_rows <- function(df_a, df_b, col_name = "conceptCode") {
  # TODO: fix logic of this function
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


get_res_score <- function(
  sub_col_data,
  anno_col_data,
  res_num,
  score_checks
) {
  
  sub_res_data <- get_result_data(sub_col_data, res_num)
  suppressWarnings(
    sub_no_match <- sub_res_data$result$dataElement$name == "NOMATCH"
  )
  
  anno_res_data <- get_result_data(anno_col_data)
  suppressWarnings(
    anno_no_match <- anno_res_data$result$dataElement$name == "NOMATCH"
  )

  both_no_match <- sub_no_match && anno_no_match
  suppressWarnings(
    if (both_no_match) {
      metric_1 <- 1
      metric_2 <- 1
      metric_3 <- 1
    } else {
      metric_1 <- magrittr::equals(
        get_de_id(sub_res_data),
        get_de_id(anno_res_data)
      ) %>% 
        as.integer()
      metric_2 <- score_concept_overlap(sub_res_data, anno_res_data)
      metric_3 <- score_value_coverage(sub_res_data, anno_res_data)
    }
  )
  
  score_1 <- metric_1*score_checks$weight[[1]]
  score_2 <- metric_2*score_checks$weight[[2]]
  score_3 <- metric_3*score_checks$weight[[3]]
  
  bonus <- (3 - res_num) * (mean(metric_1, metric_2, metric_3))

  list(step = 1:4,
       metric = c(metric_1, metric_2, metric_3, bonus),
       scores = c(score_1, score_2, score_3, bonus))

}


aggregate_res_scores <- function(res_scores, aggregate_by = "max") {
  
  scores = map_dbl(res_scores, function(x) { sum(x$score, na.rm = TRUE) })

  # Get max of all result scores
  if (aggregate_by == "max") {
    max(scores, na.rm = TRUE)
  } else {
    median(scores, na.rm = TRUE)
  }
}


get_col_score <- function(
  sub_col_data, 
  anno_col_data, 
  score_checks = get_score_checks(),
  aggregate_by = "max"
) {
  
  n_res <- max(purrr::map_dbl(sub_col_data$results, "resultNumber"))
  
  res_scores <- purrr::map(1:n_res, function(r) {
    get_res_score(
      sub_col_data,
      anno_col_data,
      res_num = r,
      score_checks = score_checks
    )
  })

  
  col_score <- aggregate_res_scores(res_scores, aggregate_by = aggregate_by)
  
  res_scores <- res_scores %>% 
    purrr::map("scores")
  
  list(
    score = col_score,
    res_score = purrr::map(res_scores, sum),
    res_data = res_scores
  )
  
}


get_col_score_table <- function(col_score) {
  
  col_score %>% 
    tibble::enframe() %>%
    tidyr::spread(name, value) %>%
    dplyr::rename(column_score = score) %>%
    tidyr::nest(data = -c(column_score)) %>%
    dplyr::mutate(
      data = purrr::map(data, function(x) {
        x$res_data %>%
          purrr::flatten() %>%
          purrr::imap_dfr(function(.x, .y) {
            .x %>% 
              tibble::as.tibble() %>% 
              dplyr::mutate(check_num = dplyr::row_number()) %>% 
              dplyr::mutate(result_num = .y) %>% 
              dplyr::mutate(result_score = sum(value)) %>% 
              dplyr::select(
                result_num, result_score, check_num, check_score = value
              )
          })
      }) 
    ) %>%
    tidyr::unnest(cols = c(column_score, data))

}


get_overall_score <- function(
  sub_data,
  anno_data,
  score_checks = get_score_checks(),
  aggregate_by = "max"
) {
  
  n_columns <- length(sub_data$columns)
  col_scores <- purrr::map(1:n_columns, function(col) {
    message(glue::glue("Scoring column {col}..."))
    
    sub_col_data <- get_column_data(sub_data, col)
    anno_col_data <- get_column_data(anno_data, col)
    
    col_score <- get_col_score(
      sub_col_data, 
      anno_col_data, 
      score_checks,
      aggregate_by
    )
    
    suppressWarnings(
      list(score = col_score$score,
           score_table = get_col_score_table(col_score) %>% 
             tibble::add_column(column_num = col, .before = 1)
      )
    )
  }) 
  
  list(
    score = purrr::map_dbl(col_scores, "score") %>% 
      mean(na.rm = TRUE),
    score_table = purrr::map_df(col_scores, "score_table")
  )
       
}


