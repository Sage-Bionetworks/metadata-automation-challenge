# Convenience function to combine string operations: (1) convert to lowercase;
# (2) trim whitespace on both sides
str_trim_lower <- function(str) {
  stringr::str_trim(stringr::str_to_lower(str))
}


# For any DEs with multiple synonyms, parse individual elements between each
# delimiter, expand into multiple rows, then recombine with any DEs that have
# a single synonym; ignore any DEs with no listed synonyms
expand_syns <- function(cadsr_df) {
  cadsr_df %>%
    dplyr::filter(!is.na(CDE_SYNONYMS_MACHINE),
                  stringr::str_detect(CDE_SYNONYMS_MACHINE, "\\|")) %>% 
    dplyr::select(CDE_ID, synonym = CDE_SYNONYMS_MACHINE) %>%
    dplyr::mutate(synonym = stringr::str_split(synonym, "\\|")) %>%
    tidyr::unnest(synonym) %>%
    dplyr::bind_rows(
      cadsr_df %>%
        dplyr::filter(!is.na(CDE_SYNONYMS_MACHINE),
                      !stringr::str_detect(CDE_SYNONYMS_MACHINE, "\\|")) %>% 
        dplyr::select(CDE_ID, synonym = CDE_SYNONYMS_MACHINE)
    ) %>% 
    dplyr::mutate(synonym = str_trim_lower(synonym))
}


# Split permissible value string by delimiter and name resulting 'parts' for 
# each element in the string
parse_pv <- function(pv) {
  pv_fields <- pv %>% 
    stringr::str_split("\\\\") %>% 
    purrr::flatten()
  
  if (length(pv_fields) == 3) {
    pv_fields %>% 
      purrr::set_names(c("value", "text_value", "concept_code")) %>% 
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
    tidyr::nest(PERMISSIBLE_VALUES) %>%
    dplyr::mutate(data = purrr::map(data, pv_to_table)) %>%
    tidyr::unnest(data)
} 


# Convenience function to pull out unique values from a specified column, 
# remove NA values, and simplify to a string vector
get_col_ov <- function(input_df, col_num) {
  input_df[[col_num]] %>% 
    unique() %>% 
    na.omit() %>% 
    as.vector()
}


match_hv_syn <- function(hv, cde_syn_df) {
  hv <- str_trim_lower(hv)
  cde_syn_df %>% 
    dplyr::filter(stringr::str_detect(synonym, hv))
}


.ov_pv_fuzzyjoin <- function(ov_df, pv_df) {
  ov_df %>%
    fuzzyjoin::stringdist_inner_join(
      pv_df,
      by = c("ov" = "pv"),
      method = "lcs",
      max_dist = 15,
    ) %>% 
    dplyr::mutate(dist = stringdist::stringdist(ov, pv, method = "jaccard")) %>% 
    dplyr::group_by(ov, CDE_ID) %>% 
    dplyr::filter(dist == min(dist)) %>% 
    dplyr::ungroup()
}


match_ov_pv <- function(ov, cde_pv_df, fuzzy = FALSE, n_hits = NULL) {
  ov_df <- tibble::tibble(ov) %>% 
    dplyr::mutate(ov = str_trim_lower(ov)) %>% 
    dplyr::distinct()
  
  if (!fuzzy) {
    hits_df <- ov_df %>%
      dplyr::inner_join(cde_pv_df, by = c("ov" = "pv"))
  } else {
    hits_df <- .ov_pv_fuzzyjoin(ov_df, cde_pv_df) %>%
      dplyr::group_by(CDE_ID) %>%
      dplyr::summarize(coverage = dplyr::n_distinct(ov), 
                       mean_dist = mean(dist)) %>% 
      dplyr::ungroup() %>% 
      dplyr::arrange(dplyr::desc(coverage), mean_dist)
    
  }
  
  if (!is.null(n_hits)) {
    dplyr::slice(hits_df, 1:n_hits)
  } else
    hits_df
}


collect_result_hv <- function(cadsr_df, de_id) {
  de_hit_df <- cadsr_df %>% 
    dplyr::filter(CDE_ID == de_id) %>% 
    dplyr::select(CDE_ID, CDE_LONG_NAME, DEC_ID, DEC_LONG_NAME, 
                  OBJECT_CLASS_IDS, PROPERTY_IDS) %>% 
    tidyr::unite(concepts, OBJECT_CLASS_IDS:PROPERTY_IDS, sep = "|", 
                 remove = TRUE) %>% 
    dplyr::mutate(concepts = stringr::str_split(concepts, "\\|"))
  
  list(
    "dataElement" = list(
      "id" = de_hit_df$CDE_ID,
      "name" = de_hit_df$CDE_LONG_NAME
    ),
    "dataElementConcept" = list(
      "id" = de_hit_df$DEC_ID,
      "name" = de_hit_df$DEC_LONG_NAME,
      "concepts" = as.list(purrr::flatten_chr(de_hit_df$concepts))
    )
  )
}


get_matched_pvs <- function(ov, pv_df) {
  ov_df <- tibble(ov) %>% 
    dplyr::mutate(ov = str_trim_lower(ov)) %>% 
    dplyr::distinct()
  
  .ov_pv_fuzzyjoin(ov_df, pv_df) %>% 
    dplyr::mutate(optdist = stringdist::stringdist(ov, pv, method = "osa")) %>% 
    dplyr::group_by(ov) %>% 
    dplyr::filter(optdist == min(optdist)) %>% 
    dplyr::sample_n(1) %>% 
    dplyr::ungroup()
}


collect_result_ov <- function(cadsr_df, de_id, ov, enum = TRUE) {
  ov_df <- tibble::tibble(ov) %>%
    dplyr::distinct()
  
  if (enum) {
    pv_hit_df <- cadsr_df %>%
      dplyr::filter(CDE_ID == de_id) %>%
      expand_pvs() %>%
      dplyr::select(CDE_ID, value, text_value, concept_code) %>%
      dplyr::mutate(pv = str_trim_lower(value)) %>%
      dplyr::distinct() %>%
      get_matched_pvs(ov, .) %>%
      fuzzyjoin::stringdist_left_join(
        ov_df, ., by = "ov",
        method = "osa",
        ignore_case = TRUE
      ) %>%
      dplyr::select(ov = `ov.x`, name = value, id = concept_code) %>%
      tidyr::replace_na(list(name = "NOMATCH"))
  } else {
    pv_hit_df <- ov_df %>% 
      dplyr::mutate(id = NA, name = "CONFORMING")
  }
  
  pv_hit_df %>%
    purrr::pmap(function(ov, id, name) {
      list(
        "value" = ov,
        "concept" = list(
          "id" = id,
          "name" = name
        )
      )
    })
}


collect_result <- function(result_num, de_id, ov, cadsr_df, enum = TRUE) {
  if (is.null(de_id)) {
    list(
      "resultNumber" = 1,
      "result" = "NOMATCH",
      "observedValues" = purrr::map(ov, function(v) {
        list(
          "value" = v,
          "concept" = list(
            "id" = NA,
            "name" = "NOMATCH"
          )
        )
      })
    )
  } else {
    list(
      "resultNumber" = result_num,
      "result" = collect_result_hv(cadsr_df, de_id),
      "observedValues" = collect_result_ov(cadsr_df, de_id, ov, enum)
    )
  }
}


annotate_column <- function(
  input_df, 
  col_num, 
  n_results,
  cadsr_df,
  cde_syn_df,
  cde_pv_df
) {
  
  col_hv <- names(input_df)[col_num]
  col_ov <- get_col_ov(input_df, col_num)
  col_hv_syn_hits <- match_hv_syn(col_hv, cde_syn_df)
  
  col_ov_pv_hits <- match_ov_pv(col_ov, cde_pv_df)
  col_de_hits <- col_hv_syn_hits %>% 
    dplyr::inner_join(col_ov_pv_hits, by = "CDE_ID") %>% 
    dplyr::distinct(CDE_ID)
  
  is_enum_de <- TRUE
  if (nrow(col_de_hits) == 0) {
    enum_hits <- cadsr_df %>% 
      filter(CDE_ID %in% col_hv_syn_hits$CDE_ID,
             VALUE_DOMAIN_TYPE == "Enumerated")
    is_enum_de <- nrow(enum_hits) > 0
    col_de_hits <- col_hv_syn_hits
  }
  is_nonenum_de <- !is_enum_de & (nrow(col_hv_syn_hits) > 0)
  
  if (is_enum_de) {
    col_de_results <- cde_pv_df %>% 
      dplyr::filter(CDE_ID %in% col_de_hits$CDE_ID) %>% 
      match_ov_pv(col_ov, ., fuzzy = TRUE, n_results)
  } else if (is_nonenum_de) {
    set.seed(0)
    col_de_results <- cadsr_df %>% 
      dplyr::filter(CDE_ID %in% col_hv_syn_hits$CDE_ID,
                    !VALUE_DOMAIN_TYPE == "Enumerated") %>% 
      dplyr::select(CDE_ID) %>% 
      dplyr::mutate(coverage = NA, mean_dist = NA) %>% 
      dplyr::sample_n(n_results, replace = TRUE) %>% 
      dplyr::distinct()
  } else {
    col_de_results <- cde_pv_df %>% 
      dplyr::slice(0)
  }
  
  if (nrow(col_de_results) > 0) {
    col_de_results %>%
      dplyr::mutate(result_num = dplyr::row_number()) %>%
      purrr::pluck("CDE_ID") %>%
      purrr::imap(~ collect_result(.y, .x, col_ov, cadsr_df, is_enum_de))
    
  } else {
    list(collect_result(1, NULL, col_ov, cadsr_df))
  }
}


prep_ref_tables <- function(cadsr_file, cadsr_pv_expanded_file = "") {
  cadsr_df <- readr::read_tsv(cadsr_file)
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
    dplyr::select(CDE_ID, pv = text_value) %>% 
    dplyr::mutate(pv = str_trim_lower(pv)) %>% 
    dplyr::distinct()
  
  list(
    cadsr_df = cadsr_df,
    cde_syn_df = cde_syn_df,
    cde_pv_df = cde_pv_df
  )
}


annotate_table <- function(
  input_df,
  cadsr_df,
  cde_syn_df,
  cde_pv_df,
  n_results = 3
) {
  list(
    "columns" = purrr::imap(names(input_df), function(.x, .y) {
      message(paste0(.y, ": ", .x))
      list(
        "columnNumber" = .y,
        "headerValue" = .x,
        "results" = annotate_column(
          input_df = input_df, 
          col_num = .y, 
          n_results = n_results, 
          cadsr_df = cadsr_df,
          cde_syn_df = cde_syn_df,
          cde_pv_df = cde_pv_df
        )
      )
    })
  )
}


run_annotator <- function(
  dataset_name, 
  cadsr_file = "/data/caDSR-dump-20190528-1320.tsv", 
  cadsr_pv_expanded_file = "/data/cadsr_pv_expanded.feather",
  n_results = 3
) {
  path_template <- "/input/{dset_name}.tsv"
  missing_anno_cols <- c("neoplasm_histologic_grade_1", 
                         "Neurological Exam Outcome")
  
  suppressWarnings(
    input_df <- readr::read_tsv(
      glue::glue(path_template, dset_name = dataset_name)
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
  
  submission_file <- glue::glue("/output/{dset_name}_baseline.json", 
                                dset_name = dataset_name)
  submission_data %>%
    jsonlite::toJSON(auto_unbox = TRUE, pretty = TRUE) %>%
    readr::write_file(submission_file)
  message(glue::glue("Output written to '{sub_file}'", 
          sub_file = submission_file))
}


