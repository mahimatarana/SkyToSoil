library(dplyr)
library(zoo)


setwd("//10.102.16.6/surf-it/Segmentation/Stats_final/outputs")
river_top<-read.csv("top_rvr_points.csv")
names(river_top)
river_toe<-read.csv("toe_rvr_points.csv")
names(river_toe)
land_top<-read.csv("top_land_points.csv")
names(land_top)
land_toe<-read.csv("toe_land_points.csv")
names(land_toe)

embankment_points<-read.csv("Embankment_segment_1m_points.csv")
names(embankment_points)




# Step 1: Deduplicate each table on the join keys
river_toe  <- river_toe  %>% distinct(type, cross_no, seg_length, Segment, .keep_all = TRUE)
land_top   <- land_top   %>% distinct(type, cross_no, seg_length, Segment, .keep_all = TRUE)
land_toe   <- land_toe   %>% distinct(type, cross_no, seg_length, Segment, .keep_all = TRUE)

# Step 2: Perform the joins again
combined_clean <- river_top %>%
  left_join(river_toe, by = c("type","cross_no","seg_length","Segment")) %>%
  left_join(land_top,  by = c("type","cross_no","seg_length","Segment")) %>%
  left_join(land_toe,  by = c("type","cross_no","seg_length","Segment"))

glimpse(combined_clean)


write.csv(combined_clean,"combined_clean_new.csv")


combined<- combined_clean %>%
  # drop empty columns if any
  select(where(~ !all(is.na(.x) | (is.character(.x) & .x == "")))) %>%
  mutate(
    # width (Euclidean distance between land top and river top)
    width = sqrt((top_land_x - top_rvr_x)^2 + (top_land_y - top_rvr_y)^2),
    
    # vertical differences (DEM elevation differences)
    vertical_distance_land  = land_top - land_toe,
    vertical_distance_river = river_top - river_toe,
    
    # bottom river point (projection)
    bottom_rvr_x = top_rvr_x,
    bottom_rvr_y = toe_rvr_y,
    
    # bottom land point (projection)
    bottom_land_x = top_land_x,
    bottom_land_y = toe_land_y,
    
    # horizontal distances
    horizontal_dist_river = sqrt((toe_rvr_x - bottom_rvr_x)^2 + (toe_rvr_y - bottom_rvr_y)^2),
    horizontal_dist_land  = sqrt((toe_land_x - bottom_land_x)^2 + (toe_land_y - bottom_land_y)^2),
    
    # slope in percentage
    slope_percent_river = (vertical_distance_river / horizontal_dist_river) * 100,
    slope_percent_land  = (vertical_distance_land  / horizontal_dist_land)  * 100,
    
    # slope in degrees
    slope_degree_river = atan(vertical_distance_river / horizontal_dist_river) * (180 / pi),
    slope_degree_land  = atan(vertical_distance_land  / horizontal_dist_land)  * (180 / pi),
    
  )%>%
  # filter out rows based on thresholds
  filter(horizontal_dist_river >= 0.25,
         horizontal_dist_land  >= 0.25,
         vertical_distance_land >= 0.25,
         vertical_distance_river >= 0.25,
         width >= 0.5)

glimpse(combined)

library(dplyr)

segment_stats <- combined%>%
  group_by(Segment) %>%
  summarise(
    n = n(),   # number of observations per segment
    segment_length = first(seg_length),
    # River slope stats
    river_mean   = mean(slope_degree_river, na.rm = TRUE),
    river_median = median(slope_degree_river, na.rm = TRUE),
    river_p20    = quantile(slope_degree_river, 0.20, na.rm = TRUE),
    river_p80    = quantile(slope_degree_river, 0.80, na.rm = TRUE),
    river_min    = min(slope_degree_river, na.rm = TRUE),
    river_max    = max(slope_degree_river, na.rm = TRUE),
    river_sd     = sd(slope_degree_river, na.rm = TRUE),
    
    # Land slope stats
    land_mean   = mean(slope_degree_land, na.rm = TRUE),
    land_median = median(slope_degree_land, na.rm = TRUE),
    land_p20    = quantile(slope_degree_land, 0.20, na.rm = TRUE),
    land_p80    = quantile(slope_degree_land, 0.80, na.rm = TRUE),
    land_min    = min(slope_degree_land, na.rm = TRUE),
    land_max    = max(slope_degree_land, na.rm = TRUE),
    land_sd     = sd(slope_degree_land, na.rm = TRUE),
    
    # Width stats
    width_mean   = mean(width, na.rm = TRUE),
    width_median = median(width, na.rm = TRUE),
    width_p20    = quantile(width, 0.20, na.rm = TRUE),
    width_p80    = quantile(width, 0.80, na.rm = TRUE),
    width_min    = min(width, na.rm = TRUE),
    width_max    = max(width, na.rm = TRUE),
    width_sd     = sd(width, na.rm = TRUE)
  )


all_segments <- combined_clean %>%
  distinct(Segment, seg_length) %>%
  arrange(Segment)

# Step 2: Join with stats (some may be missing after filter)
segment_stats_full <- all_segments %>%
  left_join(segment_stats, by = c("Segment", "seg_length" = "segment_length")) %>%
  arrange(Segment)

# Step 3: Apply moving average fill for ALL numeric columns
segment_stats_modified <- segment_stats_full %>%
  mutate(across(where(is.numeric),
                ~ ifelse(is.na(.x),
                         rollapply(.x, width = 7, align = "center", fill = NA,
                                   FUN = mean, na.rm = TRUE),
                         .x))) %>%
  mutate(averaged = ifelse(rowSums(is.na(segment_stats_full[ , sapply(segment_stats_full, is.numeric)])) > 0,
                           "averaged", "original"))


embankment_stats <- embankment_points %>%
  group_by(Segment) %>%
  summarise(
    DEM_mean   = mean(DEM, na.rm = TRUE),
    DEM_median = median(DEM, na.rm = TRUE),
    DEM_p20    = quantile(DEM, 0.20, na.rm = TRUE),
    DEM_p80    = quantile(DEM, 0.80, na.rm = TRUE),
    DEM_min    = min(DEM, na.rm = TRUE),
    DEM_max    = max(DEM, na.rm = TRUE),
    DEM_sd     = sd(DEM, na.rm = TRUE),
    DEM_n      = n()   # number of DEM points per segment
  )

segment_stats_full <- segment_stats_modified %>%
  left_join(embankment_stats, by = "Segment")

glimpse(segment_stats_full)

write.csv(segment_stats_full,"segment_stats_full_final.csv")

