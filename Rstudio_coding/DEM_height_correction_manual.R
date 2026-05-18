#Process 1: Adjusting DEMs to SRTM height

# Load necessary libraries
library(terra)

# Specify the folder where DEM files are located
dem_folder <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction"

# Get the list of all DEM files in the folder (with .tif extension)
dem_files_to_correct <- list.files(dem_folder, pattern = "\\.tif$", full.names = TRUE)

# Exclude one file of choice if necessary
exclude_file <- "modeled_dem_rf.tif"
dem_files_to_correct <- dem_files_to_correct[!basename(dem_files_to_correct) %in% exclude_file]

# Print the files to check
print(dem_files_to_correct)

# Path to the modeled DEM
model_path <- "//10.102.16.6/surf-it/Processed data_Drone/modeled_dem_rf.tif"
model_dem <- rast(model_path)

# Resample method: Bilinear or Nearest Neighbor
resample_method <- "bilinear"  # or "nearest"

# Step 3: Loop through the DEM files to correct each one
for (dem_file in dem_files_to_correct) {
  cat("Processing:", basename(dem_file), "\n")
  
  # Step 1: Load the DEM to be corrected
  dem <- rast(dem_file)
  
  # Step 2: Resample the modeled DEM to match the current DEM
  model_resampled <- tryCatch({
    resample(model_dem, dem, method = resample_method)
  }, error = function(e) {
    cat("Resampling failed for:", basename(dem_file), "\n")
    return(NULL)
  })
  
  if (!is.null(model_resampled)) {
    # Step 3: Compute the difference (dZ) between the DEM and the modeled DEM
    # We no longer use overlap_mask here, just the entire DEM
    dem_vals <- values(dem)
    model_vals <- values(model_resampled)
    
    # Remove outliers (top 25%) based on DEM values
    q75 <- quantile(dem_vals, probs = 0.75, na.rm = TRUE)
    valid_index <- which(dem_vals <= q75)  # Remove top 25% outliers (embankments, etc.)
    
    filtered_diff <- dem_vals[valid_index] - model_vals[valid_index]
    median_diff <- median(filtered_diff, na.rm = TRUE)
    
    # Step 4: Apply the correction to the DEM
    corrected_dem <- dem - median_diff
    
    # Step 5: Save the corrected DEM with "corrected_" prefix in the same folder
    # out_path <- file.path(dem_folder, paste0("corrected_", basename(dem_file)))
    
    # Step 5*: Save the corrected DEM with "corrected_" prefix in new folder
    out_folder <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/SRTM_correction"
    
    dir.create(out_folder, recursive = TRUE, showWarnings = FALSE)
    
    out_path <- file.path(out_folder, paste0("corrected_", basename(dem_file)))
    
    writeRaster(corrected_dem, out_path, overwrite = TRUE)
    
    cat("Saved:", out_path, "\n")
    
  }
}


#Process 2: Polygon creation

library(terra)

# List rasters in folder
raster_dir <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/SRTM_correction"
tif_files <- list.files(raster_dir, pattern="\\.tif$", full.names=TRUE)



# Loop through remaining rasters and convert to polygons
for (f in tif_files) {
  r <- rast(f)
  poly <- as.polygons(r, dissolve = TRUE)
  
  # activate the line below if want to save the output in same folder
  out_name <- file.path(raster_dir, paste0("poly_", basename(f), ".shp"))
  writeVector(poly, out_name, overwrite = TRUE)
  
  cat("Converted:", basename(f), "to polygons ->", out_name, "\n")
}



 library(sf)
 
 # Paths
 rtk_file <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/RTK_points.shp"
 poly_dir <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/SRTM_correction"
 out_file <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/RTK_points_with_DEM.shp"
 
 # Read RTK shapefile
 rtk <- st_read(rtk_file)
 
 # List polygon shapefiles
 poly_files <- list.files(poly_dir, pattern = "\\.shp$", full.names = TRUE)
 
 # Read polygons, keep only geometry, and add poly_id from filename
 polys_list <- lapply(poly_files, function(f) {
   p <- st_read(f)
   
   # Extract only DEM_xxx part from filename
   full_name <- tools::file_path_sans_ext(basename(f))
   dem_name <- sub(".*corrected_", "corrected_", full_name)
   
   p <- st_sf(
     DEM_name = dem_name,
     geometry = st_geometry(p)
   )
   
   return(p)
 })
 
 # Combine polygons
 polys_all <- do.call(rbind, polys_list)
 
 # Check CRS
 st_crs(rtk)
 st_crs(polys_all)
 
 # If polygon CRS is missing, assign same CRS as RTK
 if (is.na(st_crs(polys_all))) {
   st_crs(polys_all) <- st_crs(rtk)
 }
 
 # Transform RTK to polygon CRS
 rtk <- st_transform(rtk, st_crs(polys_all))
 
 # Spatial join
 rtk_with_poly <- st_join(rtk, polys_all["DEM_name"])
 
 # Ensure the output folder exists
 out_dir <- dirname(out_file)
 dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
 
 # Save output
 st_write(
   rtk_with_poly,
   out_file,
   delete_layer = TRUE,
   layer_options = "SHPT=POINTZ"
 )
 
 # Print the output file path
 cat("RTK points with DEM name saved to:", out_file, "\n")

#Process 3: Elevation correction with DEM

library(terra)
library(sf)

dem_folder <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/SRTM_correction"
out_folder <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/SRTM_correction"

rtk_file <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/RTK_points_with_DEM.shp"

rtk <- st_read(rtk_file)

dem_files <- list.files(dem_folder, pattern = "\\.tif$", full.names = TRUE)

# Rename DEM column if needed
names(rtk)[names(rtk) == "DEM_NAME"] <- "DEM_name"

# Clean RTK DEM names
rtk$DEM_name <- sub(".*DEM_", "DEM_", rtk$DEM_name)
rtk$DEM_name <- sub("\\.tif$", "", rtk$DEM_name)

for (dem_file in dem_files) {
  
  dem_name_full <- tools::file_path_sans_ext(basename(dem_file))
  
  # Clean DEM raster name the same way
  dem_name <- sub(".*DEM_", "DEM_", dem_name_full)
  dem_name <- sub("\\.tif$", "", dem_name)
  
  cat("Processing:", dem_name, "\n")
  
  dem <- rast(dem_file)
  
  # Use DEM_name
  rtk_this <- rtk[rtk$DEM_name == dem_name, ]
  
  if (nrow(rtk_this) == 0) {
    cat("No RTK points found for", dem_name, "\n")
    next
  }
  
  rtk_this <- st_transform(rtk_this, crs(dem))
  rtk_vect <- vect(rtk_this)
  
  dem_extract <- terra::extract(dem, rtk_vect)
  dem_z <- dem_extract[, 2]
  
  rtk_z <- rtk_this$RL
  
  dz <- rtk_z - dem_z
  correction <- median(dz, na.rm = TRUE)
  
  cat("Correction value:", correction, "\n")
  
  corrected_dem <- dem + correction
  
  out_path <- file.path(out_folder, paste0("RTK_", basename(dem_file)))
  writeRaster(corrected_dem, out_path, overwrite = TRUE)
  
  cat("Saved:", out_path, "\n")
}




# Process 4: Correct DEMs without RTK using overlapping RTK-corrected DEMs

library(terra)

# Folder paths
dem_folder <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/Correction with overlap"
out_folder <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/Correction with overlap"

# List all DEM files (corrected and uncorrected)
dem_files <- list.files(dem_folder, pattern = "\\.tif$", full.names = TRUE)

# Separate the RTK-corrected DEMs (those starting with "RTK_") from uncorrected DEMs
corrected_dem_files <- dem_files[grep("^RTK_", basename(dem_files))]
uncorrected_dem_files <- dem_files[!basename(dem_files) %in% basename(corrected_dem_files)]

# Extract the base names from the DEMs
corrected_dem_names <- tools::file_path_sans_ext(basename(corrected_dem_files))
uncorrected_dem_names <- tools::file_path_sans_ext(basename(uncorrected_dem_files))

# Create an empty list to store overlap pairs
overlap_pairs <- list()

# Loop over uncorrected DEMs and check overlap with corrected DEMs
for (uncorrected_dem in uncorrected_dem_files) {
  
  # Load the uncorrected DEM
  target_dem <- rast(uncorrected_dem)
  
  cat("Processing:", uncorrected_dem, "\n")
  
  # Check for overlap with each corrected DEM
  for (corrected_dem in corrected_dem_files) {
    
    # Load the corrected DEM
    reference_dem <- rast(corrected_dem)
    
    # Ensure both DEMs are in the same CRS
    if (crs(target_dem) != crs(reference_dem)) {
      reference_dem <- project(reference_dem, crs(target_dem))
    }
    
    # Compare extents of both DEMs
    target_extent <- ext(target_dem)
    reference_extent <- ext(reference_dem)
    
    # If the extents do not match, resample the reference DEM to match the target DEM's extent and resolution
    if (!identical(target_extent, reference_extent)) {
      reference_resampled <- resample(reference_dem, target_dem, method = "bilinear")
    } else {
      reference_resampled <- reference_dem
    }
    
    # Create an overlap mask where both DEMs have valid values
    overlap_mask <- !is.na(target_dem) & !is.na(reference_resampled)
    
    # If overlap exists, add to overlap pairs list
    if (sum(overlap_mask[], na.rm = TRUE) > 0) {
      
      # Extract the base names
      target_name <- tools::file_path_sans_ext(basename(uncorrected_dem))
      reference_name <- tools::file_path_sans_ext(basename(corrected_dem))
      
      # Add the pair to the list
      overlap_pairs[[length(overlap_pairs) + 1]] <- c(target_name, reference_name)
      
      cat("Found overlap: ", target_name, "with", reference_name, "\n")
    }
  }
}

# Convert the overlap pairs list to a data frame
overlap_pairs_df <- do.call(rbind, overlap_pairs)
colnames(overlap_pairs_df) <- c("target_dem", "reference_dem")

# Save the CSV
pair_csv_path <- file.path(out_folder, "overlap_pairs.csv")
write.csv(overlap_pairs_df, pair_csv_path, row.names = FALSE)

cat("Overlap pairs CSV created:", pair_csv_path, "\n")


library(terra)

# Folder containing DEMs
dem_folder <- "//10.102.16.6/surf-it/Manual_GIS & RS team/Inputs & Outputs/DEM_correction/Correction with overlap"

# Output folder
#out_folder <- file.path(dem_folder, "Overlap_corrected")
#dir.create(out_folder, recursive = TRUE, showWarnings = FALSE)

# CSV listing DEMs without RTK and their corrected overlap reference DEMs
pair_csv <- file.path(dem_folder, "overlap_pairs.csv")
pairs <- read.csv(pair_csv)

# Number of random points to sample inside overlap
n_points <- 50

# Store summary
summary_list <- list()

for (i in 1:nrow(pairs)) {
  
  target_name <- pairs$target_dem[i]  # Use target DEM name directly from the pair CSV
  reference_name <- pairs$reference_dem[i]  # Use reference DEM name directly from the pair CSV
  
  cat("\nProcessing:", target_name, "\n")
  cat("Reference:", reference_name, "\n")
  
  # Path for target and reference DEMs
  target_path <- file.path(dem_folder, paste0(target_name, ".tif"))  # No RTK_ prefix needed
  reference_path <- file.path(dem_folder, paste0(reference_name, ".tif"))  # No RTK_ prefix needed
  
  if (!file.exists(target_path)) {
    cat("Target DEM not found:", target_path, "\n")
    next
  }
  
  if (!file.exists(reference_path)) {
    cat("Reference DEM not found:", reference_path, "\n")
    next
  }
  
  # Load rasters
  target_dem <- rast(target_path)
  reference_dem <- rast(reference_path)
  
  # Resample reference DEM to match target DEM grid
  reference_resampled <- resample(reference_dem, target_dem, method = "bilinear")
  
  # Create overlap mask where both DEMs have values
  overlap_mask <- !is.na(target_dem) & !is.na(reference_resampled)
  
  # Convert overlap area to points
  overlap_points <- as.points(overlap_mask, values = TRUE, na.rm = TRUE)
  overlap_points <- overlap_points[overlap_points[[1]] == 1, ]
  
  if (nrow(overlap_points) == 0) {
    cat("No overlap found between:", target_name, "and", reference_name, "\n")
    next
  }
  
  # Randomly sample points inside overlap
  sample_indices <- sample(1:nrow(overlap_points), size = min(n_points, nrow(overlap_points)), replace = FALSE)
  sample_points <- overlap_points[sample_indices, ]
  
  # Extract elevations from both DEMs
  target_vals <- extract(target_dem, sample_points)[, 2]
  reference_vals <- extract(reference_resampled, sample_points)[, 2]
  
  # Calculate difference
  diff_vals <- reference_vals - target_vals
  
  # Remove NA values
  diff_vals <- diff_vals[!is.na(diff_vals)]
  
  if (length(diff_vals) == 0) {
    cat("No valid elevation differences found for:", target_name, "\n")
    next
  }
  
  # Use median correction because it is more robust than mean
  correction <- median(diff_vals, na.rm = TRUE)
  
  cat("Correction value:", correction, "\n")
  
  # Apply correction to target DEM
  corrected_dem <- correction + target_dem
  
  # Save corrected DEM
  out_path <- file.path(out_folder, paste0("Overlap_RTK_", target_name, ".tif"))
  writeRaster(corrected_dem, out_path, overwrite = TRUE)
  
  cat("Saved:", out_path, "\n")
  
  # Save summary
  summary_list[[length(summary_list) + 1]] <- data.frame(
    target_dem = target_name,
    reference_dem = reference_name,
    correction = correction,
    output_file = out_path
  )
}

# Save correction summary
correction_summary <- do.call(rbind, summary_list)

summary_path <- file.path(out_folder, "overlap_correction_summary.csv")
write.csv(correction_summary, summary_path, row.names = FALSE)

cat("\nSummary saved:", summary_path, "\n")
