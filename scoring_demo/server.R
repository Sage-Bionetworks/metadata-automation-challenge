#
# This is the server logic of a Shiny web application. You can run the
# application by clicking 'Run App' above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

# Define server logic required to draw a histogram
shinyServer(function(input, output) {

    selected_col <- reactiveValues()

    observeEvent(input$update_weighting, {
        selected_col$overlap_thresh = input$overlap_thresh
        selected_col$coverage_thresh = input$coverage_thresh
        selected_col$score_checks = get_score_checks(de_wt = input$de_wt,
                                                     dec_wt = input$dec_wt,
                                                     top_wt = input$top_wt,
                                                     vd_wt = input$vd_wt)
        selected_col$res_scores <- map(1:selected_col$num_res, function(r) {
            get_res_score(selected_col$sub_data,
                          selected_col$anno_data,
                          r,
                          selected_col$score_checks,
                          overlap_thresh = input$overlap_thresh,
                          coverage_thresh = input$coverage_thresh)
        })
    })

    observeEvent(input$update_cutoff, {
        selected_col$overlap_thresh = input$overlap_thresh
        selected_col$coverage_thresh = input$coverage_thresh
        selected_col$res_scores <- map(1:selected_col$num_res, function(r) {
            get_res_score(selected_col$sub_data,
                          selected_col$anno_data,
                          r,
                          selected_col$score_checks,
                          overlap_thresh = input$overlap_thresh,
                          coverage_thresh = input$coverage_thresh)
        })
    })

    observeEvent(input$column, {
        selected_col$col_num <- input$column
        selected_col$overlap_thresh = input$overlap_thresh
        selected_col$coverage_thresh = input$coverage_thresh
        selected_col$sub_data <- purrr::keep(
            submission_data$columns, ~ .x$columnNumber == input$column
        ) %>% 
            pluck(1)
        selected_col$anno_data <- purrr::keep(
            submission_annotated$columns, ~ .x$columnNumber == input$column
        ) %>% 
            pluck(1)
        selected_col$num_res <- length(selected_col$sub_data$result)
        selected_col$score_checks = get_score_checks(de_wt = input$de_wt,
                                                     dec_wt = input$dec_wt,
                                                     top_wt = input$top_wt,
                                                     vd_wt = input$vd_wt)
        selected_col$res_scores <- map(1:selected_col$num_res, function(r) {
            get_res_score(selected_col$sub_data,
                          selected_col$anno_data,
                          r,
                          selected_col$score_checks,
                          overlap_thresh = input$overlap_thresh,
                          coverage_thresh = input$coverage_thresh)
        })
        selected_col$anno_de <- get_de_table(selected_col$anno_data)
        selected_col$anno_dec <- get_dec_table(selected_col$anno_data)
        selected_col$anno_dec_concepts <- get_dec_concepts(selected_col$anno_data)
        selected_col$anno_ovs <- get_observed_values(selected_col$anno_data)
    })
    
    output$col_number <- renderText({
        input$column
    })
    
    output$header_val <- renderText({
       selected_col$sub_data$headerValue
    })
    
    output$result_opts <- renderUI({
        selectInput("result",
                    "Result number",
                    choices = 1:selected_col$num_res,
                    selected = 1)
    })
    
    output$score_table <- renderTable({
        res_num <- as.integer(input$result)
        res_score_table <- as_tibble(selected_col$res_scores[[res_num]])
        selected_col$score_checks %>%
            select(step, check, pointsIfTrue) %>%
            left_join(res_score_table, by = "step")
    })

    output$score_proc_table <- renderTable({
        selected_col$score_checks
    })

    output$res_score <- renderText({
        res_num <- as.integer(input$result)
        sum(selected_col$res_scores[[res_num]]$score, na.rm = TRUE)
    })
    
    output$col_score <- renderText({
        get_col_score(selected_col$res_scores,
                      aggregate_by = input$column_aggregate)
    })

    output$overall_score <- renderText({
        get_overall_score(submission_data, submission_annotated, selected_col$score_checks,
                          overlap_thresh = selected_col$overlap_thresh,
                          coverage_thresh = selected_col$coverage_thresh,
                          aggregate_by = input$column_aggregate)
    })

    output$sub_de_table <- renderDT({
        res_num <- as.integer(input$result)
        de_df <- get_de_table(selected_col$sub_data, res_num)
        mismatch_cols <- find_mismatch_cols(de_df, selected_col$anno_de)
        de_dt <- de_df %>% 
            datatable(
                selection = list(
                    mode = 'single'
                ),
                options = list(
                    ordering = FALSE,
                    autoWidth = FALSE,
                    dom = "t"
                ),
                rownames = FALSE
            )
        if (length(mismatch_cols)) {
            de_dt %>% 
                formatStyle(mismatch_cols, backgroundColor = 'lightpink')
        } else {
            de_dt
        }
    })
    
    output$sub_dec_table <- renderDT({
        res_num <- as.integer(input$result)
        de_df <- get_dec_table(selected_col$sub_data, res_num)
        mismatch_cols <- find_mismatch_cols(de_df, selected_col$anno_dec)
        de_dt <- de_df %>% 
            datatable(
                selection = list(
                    mode = 'single'
                ),
                options = list(
                    ordering = FALSE,
                    autoWidth = FALSE,
                    dom = "t"
                ),
                rownames = FALSE
            )   
        if (length(mismatch_cols)) {
            de_dt %>% 
                formatStyle(mismatch_cols, backgroundColor = 'lightpink')
        } else {
            de_dt
        }
    })
    
    output$sub_concepts <- renderDT({
        res_num <- as.integer(input$result)
        c_ids <- get_dec_concepts(selected_col$sub_data, res_num)
        c_df <- tibble(concepts = c_ids) 
        mismatch_rows <- find_mismatch_rows(
            c_df, 
            tibble(concepts = selected_col$anno_dec_concepts), 
            "concepts"
        )
        
        c_dt <- c_df %>% 
            datatable(
                selection = list(
                    mode = 'single'
                ),
                options = list(
                    ordering = FALSE,
                    autoWidth = FALSE,
                    dom = "t"
                ),
                rownames = FALSE
            )
        if (length(mismatch_rows)) {
            c_dt %>% 
                formatStyle(
                    "concepts", 
                    backgroundColor = styleEqual(
                        mismatch_rows, 
                        replicate(length(mismatch_rows), 'lightpink')
                    ),
                    target = "row"
                )
        } else {
            c_dt
        }
    })
    
    output$concept_overlap <- renderText({
        res_num <- as.integer(input$result)
        c_ids <- get_dec_concepts(selected_col$sub_data, res_num)
        jaccard(c_ids, selected_col$anno_dec_concepts)
    })
    
    output$sub_ovs <- renderDT({
        res_num <- as.integer(input$result)
        ov_df <- get_observed_values(selected_col$sub_data, res_num)
        if ("id" %in% names(ov_df)) {
            check_col <- "id"
        } else {
            check_col <- "name"
        }
        mismatch_rows <- find_mismatch_rows(ov_df, selected_col$anno_ovs, check_col)
        ov_dt <- ov_df %>% 
            datatable(
                selection = list(
                    mode = 'single'
                ),
                options = list(
                    ordering = FALSE,
                    autoWidth = FALSE,
                    scrollY = "300px",
                    dom = "t"
                ),
                rownames = FALSE
            )
        if (length(mismatch_rows)) {
            ov_dt %>% 
                formatStyle(
                    check_col, 
                    backgroundColor = styleEqual(
                        mismatch_rows, 
                        replicate(length(mismatch_rows), 'lightpink')
                    ),
                    target = "row"
                )
        } else {
            ov_dt
        }
    })
    
    output$ov_coverage <- renderText({
        res_num <- as.integer(input$result)
        sub_ovs <- get_observed_values(selected_col$sub_data, res_num)
        anno_ovs <- selected_col$anno_ovs
        if ("id" %in% names(sub_ovs)) {
            check_col <- "id"
        } else {
            check_col <- "name"
        }
        mismatch_rows <- find_mismatch_rows(sub_ovs, anno_ovs, check_col)
        1 - (length(mismatch_rows) / nrow(anno_ovs))
    })
    
    output$anno_de_table <- renderDT({
        selected_col$anno_de %>% 
            datatable(
                selection = list(
                    mode = 'single'
                ),
                options = list(
                    ordering = FALSE,
                    autoWidth = FALSE,
                    dom = "t"
                ),
                rownames = FALSE
            )   
    })
    
    output$anno_dec_table <- renderDT({
        selected_col$anno_dec %>% 
            datatable(
                selection = list(
                    mode = 'single'
                ),
                options = list(
                    ordering = FALSE,
                    autoWidth = FALSE,
                    dom = "t"
                ),
                rownames = FALSE
            )
    })
    
    output$anno_concepts <- renderDT({
        tibble(concepts = selected_col$anno_dec_concepts) %>% 
            datatable(
                selection = list(
                    mode = 'single'
                ),
                options = list(
                    ordering = FALSE,
                    autoWidth = FALSE,
                    dom = "t"
                ),
                rownames = FALSE
            )   
    })

    output$anno_ovs <- renderDT({
        selected_col$anno_ovs %>% 
            datatable(
                selection = list(
                    mode = 'single'
                ),
                options = list(
                    ordering = FALSE,
                    autoWidth = FALSE,
                    scrollY = "300px",
                    dom = "t"
                ),
                rownames = FALSE
            )   
    })
    
    output$sub_json <- renderJsonedit({
        jsonedit(
            selected_col$sub_data,
            "change" = htmlwidgets::JS('function(){
                console.log( event.currentTarget.parentNode.editor.get() )
              }')
        )
    })
    
    observe({
        toggle("sub_json", input$show_json)
    })

})
