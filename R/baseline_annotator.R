# Convenience function to combine string operations: (1) convert to lowercase;
# (2) trim whitespace on both sides
str_trim_lower <- function(str) {
  
  stringr::str_trim(stringr::str_to_lower(str))

}


.unnest_synonyms <- function(cadsr_df, syn_field = "CDE_SHORT_NAME") {
  
  syn_field <- dplyr::sym(syn_field)
  cadsr_df %>%
    dplyr::filter(!is.na(!!syn_field)) %>% 
    dplyr::filter(stringr::str_detect(!!syn_field, "\\|")) %>% 
    dplyr::select(CDE_ID, synonym = !!syn_field) %>%
    dplyr::mutate(synonym = stringr::str_split(synonym, "\\|")) %>%
    tidyr::unnest(synonym)
  
}


# For any DEs with multiple synonyms, parse individual elements between each
# delimiter, expand into multiple rows, then recombine with any DEs that have
# a single synonym; ignore any DEs with no listed synonyms
expand_syns <- function(cadsr_df) {
  
  dplyr::bind_rows(
    .unnest_synonyms(cadsr_df, syn_field = "CDE_SHORT_NAME"),
    .unnest_synonyms(cadsr_df, syn_field = "QUESTION_TEXT"),
    cadsr_df %>% 
      dplyr::select(CDE_ID, CDE_SHORT_NAME, QUESTION_TEXT) %>% 
      tidyr::pivot_longer(-CDE_ID, values_to = "synonym") %>% 
      dplyr::filter(!is.na(synonym),
                    !stringr::str_detect(synonym, "\\|")) %>% 
      
      dplyr::select(-name)
    
  ) %>% 
    dplyr::arrange(CDE_ID) %>% 
    dplyr::mutate(synonym = str_trim_lower(synonym)) %>%
    dplyr::distinct()
  
}


# Split permissible value string by delimiter and name resulting 'parts' for 
# each element in the string
parse_pv <- function(pv) {
  
  pv_fields <- pv %>% 
    stringr::str_split("\\\\") %>% 
    purrr::flatten()
  
  if (length(pv_fields) == 3) {
    pv_fields %>% 
      purrr::set_names(c("value", "value_meaning", "concept_code")) %>% 
      tibble::as_tibble()
  }
  
}


# Format parsed permissible value string as dataframe with a row for each 
# elemet in the string, and specific parts for each element divided by column
pv_to_table <- function(pv_str) {
  
  stringr::str_split(pv_str, "\\|") %>% 
    purrr::flatten_chr() %>% 
    purrr::map_df(~ parse_pv(.))
  
}


# Expand permissible values into tabular format for each data element in input
# reference dataframe (e.g., caDSR)
expand_pvs <- function(cadsr_df) {
  
  cadsr_df %>% 
    tidyr::nest(data = c(PERMISSIBLE_VALUES)) %>%
    dplyr::mutate(data = purrr::map(data, pv_to_table)) %>%
    tidyr::unnest(data)
  
} 


# Convenience function to pull out unique values from a specified column, 
# remove NA values, and simplify to a string vector
get_col_ov <- function(input_df, col_num) {
  
  input_df[[col_num]] %>% 
    as.character() %>% 
    unique() %>% 
    na.omit() %>% 
    as.vector()
  
}


# Make an estimated guess about whether a column represents an enumerated data
# element, based on the (alpha) diversity of row values.
guess_enumerated <- function(
  input_df, 
  col_num, 
  div_thresh = 3.85,
  verbose = TRUE
) {
  
  col_diversity <- input_df[[col_num]] %>% 
    tibble::tibble(val = .) %>% 
    dplyr::group_by(val) %>% 
    dplyr::tally() %>% 
    purrr::pluck("n") %>% 
    vegan::diversity()
  
  is_enum <- col_diversity <= div_thresh
  if (verbose) {
    message(
      glue::glue(" > Predicting column as '{vd_type}' based on value diversity ",
                 "{format(col_div, digits = 2)}",
                 vd_type = dplyr::if_else(is_enum, "Enumerated", "NonEnumerated"),
                 col_div = col_diversity)
    )
  }
  
  list(col_diversity, is_enum)
  
}


.hv_syn_regex_search <- function(hv, cde_syn_df) {
  cde_syn_df %>% 
    dplyr::filter(stringr::str_detect(synonym, hv))
}


.hv_syn_fuzzyjoin <- function(
  hv_df, 
  syn_df, 
  method = "jaccard", 
  max_dist = 0.5,
  verbose = TRUE
) {
  
  hits_df <- hv_df %>%
    fuzzyjoin::stringdist_inner_join(
      syn_df,
      by = c("hv" = "synonym"),
      method = method,
      max_dist = max_dist,
      distance_col = "dist"
    )
  if (verbose) {
    message(
      glue::glue("     >> Found {num_hits} DEs ({num_syn} total synonyms)",
                 num_hits = dplyr::n_distinct(hits_df$CDE_ID),
                 num_syn = dplyr::n_distinct(hits_df$synonym))
    )
  }
  
  hits_df
  
}


# Match header value (HV) to CDE synonyms based either on regular expression
# searching of the HV among synonym strings or, if 'fuzzy' is 'TRUE', the 
# string distance between HV and synonyms.
match_hv_syn <- function(
  hv, 
  cde_syn_df, 
  fuzzy = FALSE, 
  n_hits = 100,
  verbose = TRUE
) {
  
  hv <- str_trim_lower(hv)
  if (!fuzzy) {
    n_hits <- NULL
    if (verbose) {
      message("    + based on regular expression matching...")
    }
    hits_df <- .hv_syn_regex_search(hv, cde_syn_df) %>% 
      dplyr::mutate(dist = 0)
  } else {
    if (verbose) {
      message("    + using 'fuzzy' logic with string distance...")
    }
    hv_df <- tibble::tibble(hv = hv)
    hits_df <- .hv_syn_fuzzyjoin(hv_df, cde_syn_df, verbose = verbose) %>% 
      dplyr::arrange(dist)
    
  }
  
  if (!is.null(n_hits)) {
    if (verbose) {
      message(
        glue::glue("    + keeping top {num_hits} synonyms with minimum string ",
                   "distance to HV...",
                   num_hits = n_hits)
      )
    }
    
    top_hits <- hits_df %>% 
      dplyr::group_by(CDE_ID) %>%
      dplyr::summarize(min_dist = min(dist)) %>% 
      dplyr::ungroup() %>% 
      dplyr::arrange(min_dist) %>% 
      dplyr::slice(1:n_hits) %>% 
      purrr::pluck("CDE_ID")
  } else {
    top_hits <- hits_df$CDE_ID
  }
  
  hits_df %>% 
    dplyr::filter(CDE_ID %in% top_hits) %>% 
    dplyr::mutate(hv = hv) %>% 
    dplyr::select(CDE_ID, hv, synonym) %>% 
    dplyr::arrange(CDE_ID)
}  


# Match parts of a header value (HV) to CDE synonyms based on regular 
# expression searching of each part among synonym strings.
match_hvparts_syn <- function(hv, cde_syn_df) {
  
  hv %>% 
    snakecase::to_snake_case() %>% 
    stringr::str_split(pattern = "[^[:alnum:]]+") %>% 
    purrr::flatten_chr() %>% 
    str_trim_lower() %>% 
    purrr::keep(~ stringr::str_length(.) > 2) %>%
    purrr::map_df(function(x) {
      .hv_syn_regex_search(x, cde_syn_df) %>% 
        dplyr::mutate(hv = x) %>% 
        dplyr::select(CDE_ID, hv, synonym)
    }) %>% 
    dplyr::group_by(CDE_ID, synonym) %>%
    dplyr::mutate(n = n_distinct(hv)) %>%
    dplyr::ungroup() %>%
    dplyr::filter(n == max(n)) %>%
    dplyr::group_by(CDE_ID, synonym) %>% 
    dplyr::summarize(hvparts = stringr::str_c(hv, collapse = "|")) %>% 
    dplyr::select(CDE_ID, hvparts, synonym) %>%
    dplyr::arrange(CDE_ID)
  
}


.ov_pv_fuzzyjoin <- function(ov_df, pv_df, verbose = TRUE) {
  
  hits_df <- ov_df %>%
    fuzzyjoin::stringdist_inner_join(
      pv_df,
      by = c("ov" = "pv"),
      method = "lcs",
      max_dist = 15
    )
  
  if (verbose) {
    message(
      glue::glue("     >> Found {num_hits} DEs ({num_pv} total PVs}) ",
                 "in initial relaxed search",
                 num_hits = dplyr::n_distinct(hits_df$CDE_ID),
                 num_pv = dplyr::n_distinct(hits_df$pv))
    )
    message("    + calculating more stringent string distance...")
  }
  hits_df <- hits_df %>% 
    dplyr::mutate(dist = stringdist::stringdist(ov, pv, method = "jaccard")) 

  if (verbose) {
    message("    + keeping PV with minimum string distance to each OV...")
  }
  hits_df <- hits_df %>% 
    dplyr::group_by(ov, CDE_ID) %>% 
    dplyr::filter(dist == min(dist)) %>% 
    dplyr::ungroup()
  
  if (verbose) {
    message(
      glue::glue("     >> Kept {num_hits} DEs ({num_pv} total PVs}) ",
                 num_hits = dplyr::n_distinct(hits_df$CDE_ID),
                 num_pv = dplyr::n_distinct(hits_df$pv))
    )
  }
  
  hits_df
  
}


# Match observed values (OVs) to CDE permissible values (PVs) based either 
# on exact matching of OVs to PVs or, if 'fuzzy' is 'TRUE', the string 
# distance between OVs and PVs.
match_ov_pv <- function(
  ov, 
  cde_pv_df, 
  fuzzy = FALSE, 
  verbose = TRUE
) {
  
  ov_df <- tibble::tibble(ov) %>% 
    dplyr::mutate(ov = str_trim_lower(ov)) %>% 
    dplyr::distinct()
  
  if (verbose) {
    message(
      glue::glue(" ...matching {num_ov} OVs to {num_de} DEs ",
                 "({num_pv} total PVs)...",
                 num_ov = n_distinct(ov),
                 num_de = n_distinct(cde_pv_df$CDE_ID),
                 num_pv = n_distinct(cde_pv_df$pv))
    )
  }
  if (!fuzzy) {
    if (verbose) {
      message("    + based on exact matching...")
    }
    hits_df <- ov_df %>%
      dplyr::inner_join(cde_pv_df, by = c("ov" = "pv")) %>% 
      dplyr::mutate(pv = ov,
                    dist = 0) %>% 
      dplyr::select(CDE_ID, ov, pv, dist)
  } else {
    if (verbose) {
      message("    + using 'fuzzy' logic with string distance...")
    }
    hits_df <- .ov_pv_fuzzyjoin(ov_df, cde_pv_df, verbose = verbose) %>% 
      dplyr::select(CDE_ID, ov, pv, dist)
  }
  
  hits_df
  
}


# Summarize the results of matched PVs to OVs for each CDE.
summarize_ov_match <- function(
  col_ov_pv_hits, 
  n_hits = NULL,
  verbose = TRUE
) {
  
  if (verbose) {
    message("    + calculating OV coverage and average string distance string ",
            "distance between PVs and OVs for each DE...")
  }
  hits_df <- col_ov_pv_hits %>% 
    dplyr::group_by(CDE_ID) %>%
    dplyr::summarize(coverage = dplyr::n_distinct(ov), 
                     mean_dist = mean(dist)) %>% 
    dplyr::ungroup() %>% 
    dplyr::arrange(dplyr::desc(coverage), mean_dist)
  
  if (!is.null(n_hits)) {
    if (verbose) {
      message(
        glue::glue("    + keeping top {num_hits} DEs with minimum average ",
                   "string distance between PVs and OVs...",
                   num_hits = n_hits)
      )
    }
    dplyr::slice(hits_df, 1:n_hits)
  } else {
    hits_df
  }
  
}

.compress_hits <- function(hits_df, n_hits) {
  hits_df %>% 
    dplyr::group_by(CDE_ID) %>%
    dplyr::summarize(min_dist = min(dist)) %>% 
    dplyr::ungroup() %>% 
    dplyr::arrange(min_dist) %>% 
    dplyr::slice(1:n_hits)
}

# Reduce the number of OV-based matches according to name similarity with HV
.filter_ov_hits <- function(hv, col_ov_pv_hits, cde_syn_df, n_hits = 15) {

  hits_df <- cde_syn_df %>% 
    dplyr::filter(CDE_ID %in% col_ov_pv_hits$CDE_ID) %>% 
    dplyr::mutate(dist = stringdist::stringdist(
      hv, synonym,
      method = "jaccard",
    )) %>% 
    .compress_hits(n_hits)
  
  col_ov_pv_hits %>% 
    dplyr::filter(CDE_ID %in% hits_df$CDE_ID)
  
}


# Combine HV- and OV-based matches into a single set of CDE candidates.
combine_hv_ov_hits <- function(
  col_hv_syn_hits, 
  col_ov_pv_hits, 
  verbose = TRUE
) {
  
  hv_hits <- col_hv_syn_hits$CDE_ID
  ov_hits <- col_ov_pv_hits$CDE_ID
  num_hv_hits <- n_distinct(hv_hits)
  num_ov_hits <- n_distinct(ov_hits)
  num_common_hits <- length(intersect(hv_hits, ov_hits))
  # if (num_hv_hits < 3 | num_ov_hits < 3) {
  if (verbose) {
    message(
      " ...using union of HV- and OV-based hits."
    )
  }
  col_de_hits <- col_hv_syn_hits %>% 
    dplyr::full_join(col_ov_pv_hits, by = "CDE_ID") %>% 
    dplyr::distinct(CDE_ID)
  col_de_hits
  
  col_de_hits
  
}
    

# Select best matches among candidate hits (HV- and OV-based) for current
# column in input table.
select_de_results <- function(
  col_de_hits, 
  col_ov, 
  cde_pv_df,
  col_hv,
  cde_syn_df,
  cadsr_df, 
  is_enum_de, 
  n_results,
  verbose = TRUE
) {
  is_nonenum_de <- !is_enum_de & (nrow(col_de_hits) > 0)
  
  if (is_enum_de) {
    if (verbose) {
      message(" ...for predicted enumerated DE...")
    }
    cde_sub_pv_df <- cde_pv_df %>% 
      dplyr::filter(CDE_ID %in% col_de_hits$CDE_ID)

    col_de_results <- cde_pv_df %>% 
      dplyr::filter(CDE_ID %in% col_de_hits$CDE_ID) %>% 
      match_ov_pv(col_ov, ., fuzzy = TRUE, verbose = verbose) 

    col_de_results <- col_de_results %>%
      .filter_ov_hits(col_hv, ., cde_syn_df, n_hits = 100)
  
    col_de_results <- col_de_results %>%
      summarize_ov_match(n_results, verbose = verbose)
    col_de_results

  } else if (is_nonenum_de) {
    if (verbose) {
      message(" ...for predicted non-enumerated DE...")
    }
    set.seed(0)

    cde_sub_df <- cadsr_df %>%
      dplyr::filter(CDE_ID %in% col_de_hits$CDE_ID,
                    !VALUE_DOMAIN_TYPE == "Enumerated") %>%
      dplyr::distinct(CDE_ID)

    if (verbose) {
      message(
        glue::glue(" ...randomly selecting {num_result} results ",
                   "from {num_de} non-enumerated DEs...",
                   num_result = n_results,
                   num_de = n_distinct(cde_sub_df$CDE_ID))
      )
    }
    n_results <- min(n_results, nrow(cde_sub_df))
    col_de_results <- cde_sub_df %>%
      dplyr::mutate(coverage = NA, mean_dist = NA) %>%
      dplyr::sample_n(n_results, replace = FALSE) %>%
      dplyr::distinct()
  } else {
    col_de_results <- cde_pv_df %>%
      dplyr::slice(0)
  }
  
}


# Extract and format header value (HV) information for the current result.
collect_result_hv <- function(cadsr_df, de_id, verbose = TRUE) {
  
  de_hit_df <- cadsr_df %>% 
    dplyr::filter(CDE_ID == de_id) %>% 
    dplyr::select(CDE_ID, CDE_LONG_NAME, DEC_ID, DEC_LONG_NAME, 
                  OBJECT_CLASS_CONCEPTS, PROPERTY_CONCEPTS) %>% 
    tidyr::unite(concepts, OBJECT_CLASS_CONCEPTS:PROPERTY_CONCEPTS, sep = "|", 
                 remove = TRUE) %>% 
    dplyr::mutate(concepts = stringr::str_split(concepts, "\\|"))
  
  list(
    "dataElement" = list(
      "id" = unique(de_hit_df$CDE_ID),
      "name" = unique(de_hit_df$CDE_LONG_NAME)
    ),
    "dataElementConcept" = list(
      "id" = unique(de_hit_df$DEC_ID),
      "name" = unique(de_hit_df$DEC_LONG_NAME),
      "conceptCodes" = as.list(unique(purrr::flatten_chr(de_hit_df$concepts)))
    )
  )
  
}


# Map permissible values (PVs) of a selected CDE to a list of observed 
# values (OV), based on sequential steps of exact and 'fuzzy' matching.
get_matched_pvs <- function(ov, pv_df, verbose = TRUE) {
  
  ov_df <- tibble(ov) %>% 
    dplyr::mutate(ov = str_trim_lower(ov)) %>% 
    dplyr::distinct()
  
  hits_df <- dplyr::inner_join(ov_df, pv_df, by = c("ov" = "pv")) %>% 
    dplyr::mutate(pv = ov, dist = 0, optdist = 0)
  
  ov_df <- anti_join(ov_df, hits_df, by = "ov")
  
  .ov_pv_fuzzyjoin(ov_df, pv_df, verbose = verbose) %>%
    dplyr::mutate(optdist = stringdist::stringdist(ov, pv, method = "osa")) %>%
    dplyr::group_by(ov) %>%
    dplyr::filter(optdist == min(optdist)) %>%
    dplyr::sample_n(1) %>%
    dplyr::ungroup() %>% 
    dplyr::bind_rows(hits_df)
  
}


# Extract and format value domain (VD) information for the current result.
collect_result_vd <- function(
  cadsr_df,
  de_id,
  ov,
  enum = TRUE,
  verbose = TRUE
) { 
  
  ov_df <- tibble::tibble(ov) %>%
    dplyr::distinct()
  
  if (enum) {
    if (verbose) {
      message(
        " ...mapping PVs for current DE result match to OVs for column"
      )
    }
    pv_hit_df <- cadsr_df %>%
      dplyr::filter(CDE_ID == de_id) %>%
      expand_pvs() %>%
      dplyr::select(CDE_ID, value, value_meaning, concept_code) %>%
      dplyr::mutate(pv = str_trim_lower(value)) %>%
      dplyr::distinct() %>%
      get_matched_pvs(ov, ., verbose = verbose) %>%
      fuzzyjoin::stringdist_left_join(
        ov_df, ., by = "ov",
        method = "osa",
        ignore_case = TRUE
      ) %>%
      dplyr::select(ov = `ov.x`, value = value_meaning, concept_code, pv, 
                    dist, optdist) %>%
      dplyr::group_by(ov) %>%
      dplyr::filter(optdist == min(optdist)) %>%
      dplyr::sample_n(1) %>%
      dplyr::ungroup() %>%
      tidyr::replace_na(list(value = "NOMATCH")) %>%
      dplyr::select(-pv, -dist, -optdist)
  } else {
    pv_hit_df <- ov_df %>% 
      dplyr::mutate(concept_code = NA, value = "CONFORMING")
  }
  
  pv_hit_df %>%
    purrr::pmap(function(ov, value, concept_code) {
      list(
        "observedValue" = ov,
        "permissibleValue" = list(
          "value" = value,
          "conceptCode" = concept_code
        )
      )
    })
  
}


# Extract and format all information for the current result.
collect_result <- function(
  result_num, 
  de_id, 
  ov, 
  cadsr_df, 
  enum = TRUE,
  verbose = TRUE
) {
  
  if (is.null(de_id)) {
    list(
      "resultNumber" = 1,
      "result" = list(
        "dataElement" = list(
          "name" = "NOMATCH",
          "id" = NA
        ),
        "dataElementConcept" = list(
          "name" = "NOMATCH",
          "id" = NA,
          "conceptCodes" = list()
        ),
        "valueDomain" = purrr::map(ov, function(v) {
          list(
            "observedValue" = v,
            "permissibleValue" = list(
              "value" = "NOMATCH",
              "conceptCode" = NA
            )
        )
        })
      )
    )
  } else {
    result_data <- list(
      "resultNumber" = result_num,
      "result" = collect_result_hv(cadsr_df, de_id, verbose)
    )
    
    result_data$result[["valueDomain"]] <- collect_result_vd(
      cadsr_df, 
      de_id, 
      ov, 
      enum, 
      verbose
    )
    
    result_data
  }
  
}


# Execute all matching operations and result collection/formatting steps for
# the current column of the input table.
annotate_column <- function(
  input_df, 
  col_num, 
  n_results,
  cadsr_df,
  cde_syn_df,
  cde_pv_df,
  verbose = TRUE
) {
  
  col_hv <- names(input_df)[col_num]
  col_ov <- get_col_ov(input_df, col_num)
  
  if (verbose) {
    message(
      "Matching full HV to CDE synonyms (question text and short names)..."
    )
  }
  col_hv_syn_hits <- match_hv_syn(col_hv, cde_syn_df, verbose = verbose)
  if (verbose) {
    message(
      glue::glue(" > Found {num_hits} DE hits",
                 num_hits = dplyr::n_distinct(col_hv_syn_hits$CDE_ID))
    )
  }
  
  if (nrow(col_hv_syn_hits) == 0) {
    if (verbose) {
      message(
        "Matching deconstructed HV parts to CDE synonyms..."
      )
    }
    col_hvparts_syn_hits <- match_hvparts_syn(col_hv, cde_syn_df)
    if (verbose) {
      message(
        glue::glue(" > Found {num_hits} DE hits",
                   num_hits = dplyr::n_distinct(col_hvparts_syn_hits$CDE_ID))
      )
    }
    
    if (nrow(col_hvparts_syn_hits) > 0) {
      col_hv_syn_hits <- cde_syn_df %>%
        dplyr::filter(CDE_ID %in% col_hvparts_syn_hits$CDE_ID) %>%
        match_hv_syn(col_hv, ., fuzzy = TRUE, n_hits = 10, verbose = verbose)
    }
  }
  
  if (verbose) {
    message("Matching observed values to CDE permissible values...")
  }
  col_ov_pv_hits <- match_ov_pv(col_ov, cde_pv_df, verbose = verbose)
  if (verbose) {
    message(
      glue::glue(" > Found {num_hits} DE hits",
                 num_hits = dplyr::n_distinct(col_ov_pv_hits$CDE_ID))
    )
  }
  
  col_ov_pv_hits <- .filter_ov_hits(
    col_hv, 
    col_ov_pv_hits, 
    cde_syn_df, 
    n_hits = 100
  )
  if (verbose) {
    message(
      glue::glue(" > Reduced to {num_hits} DE hits",
                 num_hits = dplyr::n_distinct(col_ov_pv_hits$CDE_ID))
    )
  }
  
  if (verbose) {
    message("Combining DE hits from HV and OV matching...")
  }
  col_de_hits <- combine_hv_ov_hits(
    col_hv_syn_hits, 
    col_ov_pv_hits, 
    verbose = verbose
  )
  
  if (verbose) {
    message(
      glue::glue(" > Found {num_hits} combined DE hits",
                 num_hits = dplyr::n_distinct(col_de_hits$CDE_ID))
    )
  }  

  is_enum_de <- guess_enumerated(input_df, col_num, verbose = verbose)[[2]]

  if (verbose) {
    message("Selecting top results...")
  }
  col_de_results <- select_de_results(
    col_de_hits,
    col_ov,
    cde_pv_df,
    col_hv,
    cde_syn_df,
    cadsr_df,
    is_enum_de,
    n_results,
    verbose = verbose
  )
  
  if (verbose) {
    message(
      glue::glue(" > Selected {num_hits} DE hits",
                 num_hits = dplyr::n_distinct(col_de_results$CDE_ID))
    )
  }
  
  if (nrow(col_de_results) > 0) {
    col_results <- col_de_results %>%
      dplyr::mutate(result_num = dplyr::row_number()) %>%
      purrr::pluck("CDE_ID") %>%
      purrr::imap(~ collect_result(
        .y, 
        .x, 
        col_ov, 
        cadsr_df, 
        is_enum_de,
        verbose = verbose
      ))

  } else {
    col_results <- list(collect_result(
      1, 
      NULL, 
      col_ov, 
      cadsr_df,
      is_enum_de,
      verbose = verbose
    ))
  }
  
  list(
    "columnNumber" = col_num,
    "headerValue" = col_hv,
    "results" = col_results
  )
  
}


# Annotate all columns of the input table.
annotate_table <- function(
  input_df,
  cadsr_df,
  cde_syn_df,
  cde_pv_df,
  n_results = 3,
  verbose = FALSE
) {
  
  list(
    "columns" = purrr::imap(names(input_df), function(.x, .y) {
      col_msg <- glue::glue("Annotating column {.y}: {.x}...")
      cat(glue::glue("{col_msg}\r"))
      start_time <- Sys.time()
      col_data <- annotate_column(
        input_df = input_df, 
        col_num = .y, 
        n_results = n_results, 
        cadsr_df = cadsr_df,
        cde_syn_df = cde_syn_df,
        cde_pv_df = cde_pv_df,
        verbose = verbose
      )
      end_time <- Sys.time()
      cat(glue::glue("{col_msg}DONE. ",
                     "({format(end_time - start_time, digits = 3)} elapsed)\n\n"))
      col_data
    })
  )
  
}


# Load and preprocess reference tables.
prep_ref_tables <- function(cadsr_file, cadsr_pv_expanded_file = "") {
  
  cadsr_df <- readr::read_tsv(cadsr_file, col_names = T)
  cde_syn_df <- expand_syns(cadsr_df)
  
  if (!fs::file_exists(cadsr_pv_expanded_file)) {
    pv_concept_df <- cadsr_df %>%
      dplyr::filter(VALUE_DOMAIN_TYPE == "Enumerated",
                    !is.na(PERMISSIBLE_VALUES)) %>% 
      dplyr::select(CDE_ID, PERMISSIBLE_VALUES) %>%
      expand_pvs()
    
    feather::write_feather(pv_concept_df, cadsr_pv_expanded_file)
  } else {
    pv_concept_df <- feather::read_feather(cadsr_pv_expanded_file)
  }
  
  cde_pv_df <- pv_concept_df %>% 
    dplyr::select(CDE_ID, pv = value) %>% 
    dplyr::mutate(pv = str_trim_lower(pv)) %>% 
    dplyr::distinct()
  
  list(
    cadsr_df = cadsr_df,
    cde_syn_df = cde_syn_df,
    cde_pv_df = cde_pv_df
  )
  
}


# Execute all annotation steps for a specified input dataset.
run_annotator <- function(
  dataset_name, 
  cadsr_file = "/data/caDSR-export.tsv", 
  cadsr_pv_expanded_file = "/user_data/cadsr_pv_expanded.feather",
  n_results = 3
) {
  
  path_template <- "/input/{dset_name}.tsv"
  missing_anno_cols <- c("neoplasm_histologic_grade_1",
                         "Neurological Exam Outcome")
  input_path <- glue::glue(path_template, dset_name = dataset_name)
  num_cols <- readr::count_fields(input_path, tokenizer = tokenizer_tsv(), n_max = 1)
  
  suppressWarnings(
    input_df <- readr::read_tsv(
      input_path,
      col_types = str_c(rep("c", num_cols), collapse = ""),
      col_names = TRUE
    ) %>% 
      dplyr::select_at(dplyr::vars(-dplyr::one_of(missing_anno_cols)))
  )
  message("Input table loaded.\n")
  
  ref_tables <- prep_ref_tables(
    cadsr_file = cadsr_file,
    cadsr_pv_expanded_file = cadsr_pv_expanded_file)
  message("Reference tables loaded.\n")

  message("Annotating columns...\n")
  submission_data <- annotate_table(
    input_df = input_df,
    n_results = n_results,
    cadsr_df = ref_tables$cadsr_df,
    cde_syn_df = ref_tables$cde_syn_df,
    cde_pv_df = ref_tables$cde_pv_df
  )
  
  submission_file <- glue::glue("/output/{dset_name}-Submission.json", 
                                dset_name = dataset_name)
  submission_data %>%
    jsonlite::toJSON(auto_unbox = TRUE, pretty = TRUE) %>%
    readr::write_file(submission_file)
  
  message(glue::glue("Output written to '{sub_file}'", 
          sub_file = submission_file))
  
}
