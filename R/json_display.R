column_df <- json_data %>% 
  gather_object() %>% 
  gather_array() %>% 
  select(-name) %>% 
  gather_object()

hv_df <- column_df %>% 
  filter(name == "headerValue") %>% 
  tidyjson::append_values_string("headerValue") %>% 
  select(-`document.id`, -name) %>% 
  as_tibble()
  
  
results_df <- column_df %>% 
  filter(name == "results") %>% 
  gather_array() %>% 
  select(-`document.id`, -name, -`array.index.2`)

result_df <- results_df %>% 
  gather_object() %>% 
  filter(name == "result") %>% 
  select(-name)

header_de_df <- result_df %>% 
  spread_all() %>% 
  select(`array.index`, contains("dataElement"))

header_concepts_df <- result_df %>% 
  gather_object() %>% 
  filter(name == "dataElementConcept") %>% 
  select(-name) %>% 
  gather_object() %>% 
  filter(name == "concepts") %>% 
  select(-name) %>% 
  gather_array() %>%
  tidyjson::append_values_string("concept") %>% 
  select(`array.index`, concept) %>% 
  group_by(`array.index`) %>% 
  summarize(concepts = str_c(concept, collapse = ", "))

header_anno_df <- header_de_df %>% 
  left_join(header_concepts_df, by = "array.index") %>% 
  rename(`dataElementConcept.concepts` = concepts) %>% 
  as_tibble()

ov_anno_df <- results_df %>% 
  gather_object() %>% 
  filter(name == "observedValues") %>% 
  select(-name) %>% 
  gather_array() %>% 
  spread_all() %>% 
  select(-`array.index.2`) %>% 
  as_tibble()


ov_anno_df %>% 
  filter(array.index %>% between(14, 22)) %>%
  mutate_at(c("value"), function(s) {
    str_trim(s) %>% str_c("`", ., "`")
  }) %>% 
  mutate_at(c("value", "concept.name", "concept.id"), function(s) {
    str_trim(s) %>% str_c("<li>", ., "</li>")
    }
  ) %>% 
  group_by(`array.index`) %>%  
  summarise_all(~ str_c(., collapse = "")) %>%
  mutate_at(c("value", "concept.name", "concept.id"), function(s) {
    str_trim(s) %>% str_c("<ul>", ., "</ul>")
    }
  ) %>% 
  left_join(header_anno_df, .) %>% 
  filter(array.index %>% between(14, 22)) %>% 
  left_join(hv_df, .) %>% 
  filter(array.index %>% between(14, 22)) %>% 
  mutate_at(c("headerValue"), function(s) {
    str_trim(s) %>% str_c("`", ., "`")
  }) %>% 
  knitr::kable()
