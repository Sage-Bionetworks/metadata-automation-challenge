
input_dir <- "data/manually-curated/"
data_dir <- "data/manually-curated_annotated/"

dataset_ids <- list(
  "APOLLO-2" = "syn21088742",
  "Outcome-Predictors" = "syn21088743",
  "REMBRANDT" = "syn21088744",
  "ROI-Masks" = "syn21088745"
)
datasets <- names(dataset_ids)

walk(1:length(dataset_ids), function(d) {
# walk(2, function(d) {
  dataset_num <- d
  dataset_name <- datasets[dataset_num]
  cat(glue::glue('### {dataset_name}'))
  cat("\n\n")

  path_template <- "{dir_name}{prefix}{dset_name}.{ext}"
  input_path <- glue::glue(path_template,
                           dir_name = input_dir,
                           prefix = "",
                           dset_name = dataset_name,
                           ext = "tsv")
  num_cols <- readr::count_fields(input_path, tokenizer = tokenizer_tsv(), n_max = 1)
  input_df <- readr::read_tsv(
    input_path,
    col_types = str_c(rep("c", num_cols), collapse = "")
  ) 

  anno_path <- glue::glue(path_template,
                          dir_name = data_dir,
                          prefix = "Annotated-",
                          dset_name = dataset_name,
                          ext = "json")
  anno_data <- jsonlite::read_json(
    anno_path
  )
  
  anno_table_path <- glue::glue(path_template,
                                dir_name = data_dir,
                                prefix = "Annotated-",
                                dset_name = dataset_name,
                                ext = "txt")
  
  num_cols <- readr::count_fields(anno_table_path, tokenizer = tokenizer_tsv(), n_max = 1)
  anno_df <- readr::read_tsv(anno_table_path,
                             col_names = FALSE,
                             col_types = str_c(rep("c", num_cols), collapse = "")) %>%
    purrr::set_names(format_column_names(., 1))
  
  input_col_names <- names(input_df)
  anno_col_names <- map_chr(anno_data$columns, "headerValue")
  print(setdiff(input_col_names, anno_col_names))
  print(setdiff(anno_col_names, input_col_names))
  testthat::expect_equal(input_col_names, anno_col_names)


  input_col_ovs <- map(input_df, ~ as.vector(na.omit(as.character(unique(str_trim(.)))))) %>%
    set_names(NULL)
  anno_col_ovs <- map(anno_data$columns, function(c) {
    map_chr(c$results[[1]]$result$valueDomain, "observedValue")
  })
  ov_check <- all.equal(input_col_ovs, anno_col_ovs)
  if (length(ov_check) > 0 && ov_check != TRUE) {
    ov_err_cols <- map_int(
      ov_check,
      ~ as.integer(parse_number(str_extract(., "Component [0-9]*")))
    )
    walk(unique(ov_err_cols), function(err_col) {
      cat(glue::glue('#### Issue in column {err_col} ',
                     '("{input_col_names[[err_col]]}")'))
      cat("\n\n")

      col_vd_df <- anno_df %>%
        slice(-1) %>%
        .[, (2*err_col - 1):(2*err_col)] %>%
        collate_value_domain() %>%
        .$data %>%
        .[[1]] %>%
        filter(!is.na(value))

      multi_anno <- col_vd_df %>%
        group_by(value) %>%
        tally() %>%
        filter(n > 1) %>%
        pluck("value")

      if (!is.null(multi_anno)) {
        
        cat("The following values have multiple annotations:\n")
        walk(multi_anno,
             function(val) {
               cat(glue::glue('- "{val}"'))
               multi_anno_df <- col_vd_df %>% filter(value == val) %>%
                 mutate(value = str_c("`", value, "`"))
               cat("\n")
               md_table <- knitr::kable(multi_anno_df, 
                                        col.names = colnames(multi_anno_df))
               md_table[[2]] <- str_replace(md_table[[2]], "NA.*\\|", "---|")
               print(md_table)
             }
        )
      }
      cat("\n")

    })
  }
})

