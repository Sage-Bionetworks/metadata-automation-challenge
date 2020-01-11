
# functions ---------------------------------------------------------------

format_column_names <- function(table, num_results = 3, offset = 0) {
  bag_length = num_results + 1
  col_names <- table %>% tidyr::gather(col, val) %>% 
    dplyr::mutate(col_num = readr::parse_number(col) - offset) %>% 
    dplyr::mutate(col_type = dplyr::case_when(
      (col_num %in% seq(1, ncol(table), bag_length)) ~ "value",
      TRUE ~ "result"
    )) %>%
    dplyr::mutate(col_bag = floor((col_num - 1) / bag_length) + 1) %>%
    dplyr::mutate(result_num = col_num - (bag_length*col_bag) + bag_length - 1) %>%
    dplyr::mutate(col_label = dplyr::case_when(
      col_type == "value" ~ stringr::str_c("column", col_bag, "_", col_type),
      TRUE ~ stringr::str_c("column", col_bag, "_", col_type, "_", result_num)
    )) %>%
    distinct(col_label) %>%
    dplyr::pull(col_label)
  col_names
}

get_header_data <- function(table) {
  header_data <- table %>% 
    slice(1) %>% 
    gather(col, val) %>% 
    separate(col, c("columnNumber", "source", "source_num")) %>% 
    filter(!is.na(val))
  header_data
}

parse_result <- function(result_number, result) {
  if (result == "NOMATCH") {
    return(
      list(resultNumber = as.integer(result_number),
           result = list(
             "dataElement" = list(
               "name" = "NOMATCH",
               "id" = NA
             ),
             "dataElementConcept" = list(
               "name" = "NOMATCH",
               "id" = NA,
               "conceptCodes" = list()
             )
           )
      )
    )
  }
  result_data <- stringr::str_split(result, "\\\\")[[1]]
  result_val <- list(dataElement = parse_de(result_data[1]),
                     dataElementConcept = parse_dec(result_data[2]))
  list(resultNumber = as.integer(result_number),
       result = result_val)
}

collect_results <- function(column_results) {
  column_results %>% 
    tidyr::nest(-source_num) %>% 
    dplyr::mutate(result_data = purrr::map2(source_num, data, function(x, y) {
      parsed_res <- pull(y, val) %>%
        parse_result(x, .)
      parsed_res[["observedValues"]] <- y$ovs[[1]]
      parsed_res
    })) %>%
    pull(result_data)
}

parse_de <- function(de_str) {
  de_parts <- stringr::str_split(de_str, " ")[[1]]
  list(
    id = as.integer(clean_id(de_parts[1])),
    name = stringr::str_trim(
      stringr::str_c(de_parts[-1], collapse = " ")
    )
  )
}

parse_dec <- function(dec_str) {
  dec_str <- stringr::str_trim(dec_str)
  dec_id <- as.integer(clean_id(stringr::str_extract(dec_str, "DEC:[0-9]*")))
  dec_parts <- stringr::str_replace(dec_str, "DEC:[0-9]*", "") %>% 
    stringr::str_trim() %>% 
    clean_dec() %>% 
    stringr::str_split("(\\|| )") %>% 
    .[[1]] %>% 
    collect_dec_parts()
  
  list(id = as.integer(stringr::str_trim(dec_id)),
       name = stringr::str_trim(dec_parts$name),
       conceptCodes = as.list(stringr::str_trim(dec_parts$concepts))
  )
}

collect_dec_parts <- function(dec_parts) {
  concepts <- purrr::keep(dec_parts, ~ stringr::str_detect(., ":"))
  list(
    name = stringr::str_trim(
      stringr::str_c(setdiff(dec_parts, concepts), collapse = " ")
    ),
    concepts = concepts
  )
}

clean_dec <- function(dec_str) {
  dec_parts <- stringr::str_split(dec_str, " ")[[1]]
  if (sum(str_detect(dec_parts, "\\|")) > 1) {
    dec_table <- tibble::tibble(part = dec_parts) %>%
      separate(part, into = c("name", "id"), sep = "\\|") %>% 
      mutate(id = str_c("ncit:", id, sep = ""))
    dec_name <- str_c(dec_table$name, collapse = " ")
    dec_concepts <- str_c(dec_table$id, collapse = " ")
    dec_str <- paste0(dec_name, "|", dec_concepts)
  }
  dec_str
}

parse_concept <- function(concept_str) {
  concept_parts <- stringr::str_split(concept_str, "\\|")[[1]]
  list(value = stringr::str_trim(concept_parts[1]),
       conceptCode = stringr::str_trim(concept_parts[2]))
}

clean_id <- function(id_str) {
  stringr::str_replace(id_str, ".*:", "")
}

parse_column <- function(column_number, column_data) {
  col_val = column_data %>% 
    dplyr::filter(source == "value") %>% 
    dplyr::pull(val)
  col_res = column_data %>% 
    dplyr::filter(source == "result") %>% 
    collect_results()
  
  list(columnNumber = column_number,
       headerValue = col_val,
       results = col_res)
}

observed_values_to_list <- function(ov_df) {
  ov_df %>% 
    filter(!is.na(value)) %>% 
    replace_na(list(result = "NOMATCH")) %>% 
    distinct() %>% 
    pmap(function(value, result) {
      list(rowValue = value,
           permissibleValue = parse_concept(result))
      
    })
}

collate_observed_values <- function(row_data) {
  row_data_spread <- row_data %>% 
    gather(col, val) %>% 
    separate(col, c("columnNumber", "source", "source_num")) %>% 
    group_by(columnNumber, source, source_num) %>% 
    mutate(row = row_number()) %>% 
    ungroup()
  
  row_data_spread %>% 
    filter(source == "value") %>%
    left_join(filter(row_data_spread, source == "result"),
              by = c("columnNumber", "row")) %>%
    rename(value = val.x, resultNumber= source_num.y, result = val.y) %>%
    select(-source.x, -source_num.x, -source.y) %>%
    select(-row) %>%
    distinct() %>%
    group_by(columnNumber, resultNumber) %>%
    nest()
}

get_observed_data <- function(table) {
  row_data <- slice(table, -1)
  
  row_data %>%
    collate_observed_values() %>%
    mutate(data = map(data, observed_values_to_list)) %>%
    rename(ovs = data)
}

table2json <- function(table) {
  header_data <- get_header_data(table)
  ov_data <- get_observed_data(table)
  
  list(
    columns = header_data %>%
      dplyr::left_join(
        ov_data, 
        by = c("columnNumber", "source_num" = "resultNumber")
      ) %>% 
      dplyr::group_by(columnNumber) %>%
      tidyr::nest() %>%
      dplyr::ungroup() %>%
      dplyr::mutate(columnNumber = readr::parse_number(columnNumber)) %>%
      dplyr::mutate(col_data = map2(columnNumber, data, parse_column)) %>%
      dplyr::pull(col_data)
  ) %>%
    jsonlite::toJSON(auto_unbox = TRUE, pretty = TRUE)
}

get_filepath_base <- function(filepath) {
  fs::path_ext_remove(filepath)
}

format_submission <- function(filepath, num_results = 3) {
  fp_base <- get_filepath_base(filepath)
  table <- readr::read_tsv(filepath,
                           col_names = FALSE)
  table %>%
    purrr::set_names(format_column_names(., num_results)) %>%
    table2json() %>%
    readr::write_file(paste0(fp_base, ".json"))
}

# execute -----------------------------------------------------------------

table_file <- "data/manually-curated_annotated/Annotated-APOLLO-2.tsv"
format_submission(table_file, num_results = 1)

anno_dir <- "data/manually-curated_annotated/"
fs::dir_ls(anno_dir, glob = "*.tsv") %>% 
  walk(~ format_submission(filepath = ., num_results = 1))
