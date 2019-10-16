#
# This is the user-interface definition of a Shiny web application. You can
# run the application by clicking 'Run App' above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

# Define UI for application that draws a histogram
shinyUI(fluidPage(

    # Application title
    titlePanel("Metadata Automation Scoring"),
    useShinyjs(),

    sidebarLayout(
        sidebarPanel(
            width = 3,
            selectInput("column",
                        "Column number",
                        choices = 1:8,
                        selected = 1),
            fluidRow(
                column(
                    width = 12,
                    h5(
                        strong("Header value:"), 
                        code(textOutput("header_val", inline = TRUE))
                    )
                )
            ),
            hr(),

                
            h6(strong("Match Weightings")),
            wellPanel(
                div(
                    style = "font-size:85%;text-align:center;",
                    fluidRow(
                        column(
                            6,
                            textInput("de_wt", "DE", 
                                      value = 1.0, width = "100%")
                        ),
                        column(
                            6,
                            textInput("dec_wt", "DEC", 
                                      value = 1.0, width = "100%")
                        )
                    ),
                    fluidRow(
                        column(
                            12,
                            textInput("top_wt", "Top Result", 
                                      value = 2.0, width = "100%")
                        )
                    ),
                    fluidRow(
                        column(
                            12,
                            textInput("vd_wt", "VD Coverage", 
                                      value = 0.5, width = "100%")
                        )
                    )
                )
            ),
            h6(strong("Metric Cutoffs")),
            wellPanel(
                div(
                    style = "font-size:85%;text-align:center;",
                    fluidRow(
                        column(
                            12,
                            sliderInput("overlap_thresh", "Overlap (Jaccard)", min = 0, max = 1,
                                        step = 0.1, value = 0.5, width = "100%")
                        )
                    ),
                    fluidRow(
                        column(
                            12,
                            sliderInput("coverage_thresh", "VD Coverage", min = 0, max = 1,
                                        step = 0.1, value = 0.8, width = "100%")
                        )
                    ),
                    actionButton("update_cutoff", "Update Cutoffs")
                )
            )

        ),

        # Show a plot of the generated distribution
        mainPanel(
            width = 9,
            fluidRow(
                wellPanel(
                    fluidRow(
                        column(
                            4,
                            uiOutput("result_opts")
                        ),
                        column(
                            8,
                            h5("Result score"),
                            textOutput("res_score")
                        )
                    )
                )
            ),
            fluidRow(
                tabsetPanel(
                    tabPanel(
                        "Score Breakdown",
                        fluidRow(
                            column(
                                12,
                                tableOutput("score_table")
                            )
                        )
                    ),
                    tabPanel(
                        "Score Procedure",
                        fluidRow(
                            column(
                                12,
                                tableOutput("score_proc_table")
                            )
                        )
                    )
                )
            ),
            br(), br(),
            fluidRow(
                tabsetPanel(
                    tabPanel(
                        "Header",
                        br(),
                        fluidRow(
                            column(
                                6,
                                h4(strong("Submitted data"))
                            ),
                            column(
                                6,
                                h4(strong("Annotated data"))
                            )
                        ),
                        fluidRow(
                            column(
                                12,
                                h5(strong("Data Element (DE)"))
                            )
                        ),
                        fluidRow(
                            column(
                                6,
                                DTOutput("sub_de_table")
                            ),
                            column(
                                6,
                                DTOutput("anno_de_table")
                            )
                        ),
                        br(), br(),
                        fluidRow(
                            column(
                                12,
                                h5(strong("Data Element Concept (DEC)"))
                            )
                        ),
                        fluidRow(
                            column(
                                6,
                                DTOutput("sub_dec_table"),
                                DTOutput("sub_concepts", width = "50%"),
                                br(),
                                p(
                                    strong("Concept Overlap:"), 
                                    textOutput("concept_overlap", inline = TRUE)
                                )
                            ),
                            column(
                                6,
                                DTOutput("anno_dec_table"),
                                DTOutput("anno_concepts", width = "50%")
                            )
                        )
                    ),
                    tabPanel(
                        "Values",
                        br(),
                        fluidRow(
                            column(
                                6,
                                h4(strong("Submitted data"))
                            ),
                            column(
                                6,
                                h4(strong("Annotated data"))
                            )
                        ),
                        fluidRow(
                            column(
                                12,
                                h5(strong("Observed Values & Matches"))
                            )
                        ),
                        fluidRow(
                            column(
                                6,
                                DTOutput("sub_ovs"),
                                br(),
                                p(
                                    strong("Value Domain Coverage:"), 
                                    textOutput("ov_coverage", inline = TRUE)
                                )
                            ),
                            column(
                                6,
                                DTOutput("anno_ovs")
                            )
                        )
                        
                    )
                )
            ),
            hr(),
            actionButton(
                "show_json",
                "Show/hide JSON"
            ),
            br(), br(),
            jsoneditOutput("sub_json")
        )
    )
))
