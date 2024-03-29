# Library load ------------------------------------------------------------

library(readxl)
library(tidyverse)
library(rgbif)

# Data import and tidy ----------------------------------------------------

ym_renames = read_excel("data/ym_renames.xlsx")

main_datasets = ym_renames |> 
  filter(DataSourceTitle == c("WoRMS", "GBIF Backbone Taxonomy")) |> 
  select(MatchedCanonical, TaxonId, DataSourceTitle) |> 
  arrange(DataSourceTitle) |> 
  janitor::clean_names()
  
clean_data = main_datasets |> 
  mutate(taxon_id = str_remove_all(taxon_id, "urn:lsid:https://marinespecies.org:taxname:"))

gbif_dataset = clean_data |> 
  filter(data_source_title == "GBIF Backbone Taxonomy") |>
  mutate(global_occ_count = NA, aq_occ_count = NA) 

worms_dataset = clean_data |> 
  filter(data_source_title == "WoRMS") |>
  mutate(global_occ_count = NA, usage_key = NA)

# Global count search ------------------------------------------------------------
nrow = 25
# Count global occurrence for the GBIF dataset
for (i in 1:nrow) {
  taxon_key <- gbif_dataset$taxon_id[i]
  global_occ_count <- occ_count(taxonKey = taxon_key)
  gbif_dataset$global_occ_count[i] <- global_occ_count
}
# Count global occurrence for the WoRMS dataset
for (i in 1:nrow) {
  taxon_key <- name_backbone(worms_dataset$matched_canonical[i])$usageKey
  if(!is.numeric(taxon_key)) {
    taxon_key_verb<- name_backbone_verbose(worms_dataset$matched_canonical[i])
    taxon_key = taxon_key_verb[[2]]$usageKey[1]
  }
  worms_dataset$usage_key[i] <- taxon_key
  global_occ_count <- occ_count(taxonKey = taxon_key)
  worms_dataset$global_occ_count[i] <- global_occ_count
}


# Antarctic count search --------------------------------------------------

measo_shape <- "POLYGON((180 -44.3, 173 -44.3, 173 -47.5, 170 -47.5, 157 -47.5, 
157 -45.9, 150 -45.9, 150 -47.5, 143 -47.5, 143 -45.8, 140 -45.8, 140 -44.5, 
137 -44.5, 137 -43, 135 -43, 135 -41.7, 131 -41.7, 131 -40.1, 115 -40.1, 
92 -40.1, 92 -41.4, 78 -41.4, 78 -42.3, 69 -42.3, 69 -43.3, 47 -43.3, 47 -41.7, 
30 -41.7, 12 -41.7, 12 -40.3, 10 -40.3, 10 -38.3, -5 -38.3, -5 -38.9, -9 -38.9, 
-9 -40.2, -13 -40.2, -13 -41.4, -21 -41.4, -21 -42.5, -39 -42.5, -39 -40.7, 
-49 -40.7, -49 -48.6, -54 -48.6, -54 -55.7, -62.7972582608082 -55.7, -64 -55.7, 
-64 -57.8, -71 -57.8, -71 -58.9, -80 -58.9, -80 -40, -125 -40, -167 -40, 
-167 -42.6, -171 -42.6, -171 -44.3, -180 -44.3, -180 -90, 0 -90, 180 -90, 180 -44.3))"

# Count aq occurrence for the GBIF dataset
for (i in 1:nrow) {
  taxon_key <- gbif_dataset$taxon_id[i]
  aq_occ_count <-occ_count(geometry = measo_shape, taxonKey = taxon_key)
  gbif_dataset$aq_occ_count[i] <- aq_occ_count
}
# Count aq occurrence for the WoRMS dataset
for (i in 1:nrow) {
  taxon_key <- worms_dataset$usage_key[i]
  aq_occ_count <- occ_count(geometry = measo_shape, taxonKey = taxon_key)
  worms_dataset$aq_occ_count[i] <- aq_occ_count
}

# Proportion of counts calculation ----------------------------------------

prop_calc = function(df) {
  df |> 
    mutate(aq_presence_proportion = aq_occ_count / global_occ_count) |> 
    mutate(aq_presence_proportion = format(aq_presence_proportion, scientific = FALSE)) |> 
    mutate(aq_presence_proportion = round(as.numeric(aq_presence_proportion), digits = 2))
}

gbif_dataset_prop = prop_calc(gbif_dataset)
worms_dataset_prop = prop_calc(worms_dataset)

# Row selection -----------------------------------------------------------

join_data = full_join(gbif_dataset_prop,worms_dataset_prop)
join_clean_data = join_data |> 
  filter(aq_presence_proportion > 0.5) |> 
  mutate(in_worms = ifelse(data_source_title == "WoRMS", T, F))

# In WoRMS/RAS ? --------------------------------------------------------------

worms_datasetkey = "2d59e5db-57ad-41ff-97d6-11f5fb264527"
ras_datasetcode = "e9c227e0-adea-4530-8b2c-e16b06553b6d"

if (!join_clean_data$in_worms[1]) {
  test <- occ_search(scientificName = join_clean_data$matched_canonical[1])
  if (any(str_detect(test$data$datasetKey, worms_datasetkey))) {
    join_clean_data <- mutate(join_clean_data, in_worms = TRUE)
  }
  if (any(str_detect(test$data$datasetKey, ras_datasetcode))) {
    join_clean_data <- mutate(join_clean_data, in_ras = TRUE)
  }
}