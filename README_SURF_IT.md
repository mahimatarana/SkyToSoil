# Drone Survey & LiDAR Data Processing Pipeline

A field-to-analysis workflow for drone-based topographic surveys using DJI LiDAR, DJI Terra, CloudCompare, ArcMap, and R — designed for embankment monitoring and elevation analysis.

---

## Overview

This pipeline covers the full lifecycle of a drone survey mission: pre-flight setup through final embankment statistics. It was developed for LiDAR-based mapping of river embankments and produces georeferenced DEMs, cross-section profiles, and per-segment elevation statistics.

**Key outputs:**
- Orthomosaic (2D) raster maps
- Classified LiDAR point clouds (.las)
- Corrected Digital Elevation Models (DEM)
- Embankment cross-section geometries
- Per-segment statistics (height, width, land slope, river slope)

---

## Workflow Summary

```
Field Operation → Raw Data Processing → Elevation Correction → Segmentation & Statistics
     (Step 1)           (Step 2)               (Step 3)               (Step 3)
```

---

## Step 1 — Field Operation

### Hardware
- DJI drone with L2 LiDAR sensor
- RTK base station
- Remote Controller (RC)

### Pre-flight Checklist
- Attach L2 sensor and insert fully charged batteries
- Power on RTK, mount on stand, confirm battery level
- Power on drone → RC → confirm RTK Signal: Normal
- Enable all obstacle avoidance sensors
- Upload pre-planned flight path
- Flight distance limit: **1.5–2.0 km**
- Max altitude: **150 m**
- Clear 5 m radius around drone before takeoff

### In-flight Guidelines
- Max mission duration: **22 minutes**
- Initiate Return to Home (RTH) at **30–35% battery** if far from home point
- During battery swap: keep at least one battery pair in the drone
- Wind speed threshold: **37 m/s** — recall drone immediately if exceeded
- Maintain visual line-of-sight at all times

### Post-flight
1. Power off drone → RTK
2. Detach L2 sensor and remove all batteries
3. Fold wings and pack securely

---

## Step 2 — Data Processing

### Folder Structure

For each grid, create the following directory layout:

```
Grid_101/
├── DEM/
├── Intermediate/
├── Lidar_3D/
├── Ortho_2D/
├── Photos/
├── Raw_data/
└── Terra/
```

### 2A — DJI Terra: 2D Orthomosaic

1. Open DJI Terra → New Mission → **Visible Light**
2. Name mission (e.g., `Grid_101_2D`), add raw image folders
3. Select **2D Map** under Parameters → Start Reconstruction
4. Export zip to `Terra/` folder
5. Copy `result.prj`, `result.tfw`, `result.tif` from the Terra output folder into `Ortho_2D/` and rename (e.g., `Grid_101_2D`)

### 2B — DJI Terra: 3D LiDAR Point Cloud

1. New Mission → **LiDAR Point Cloud**, name it (e.g., `Grid_101_3D`)
2. Add raw data folders under Files
3. Enable: **Ground Point Classification**, **DEM**, **Contour**
4. Verify UTM zone under Advanced: `WGS 84 / UTM Zone 45N`
5. Start Reconstruction → Export zip to `Terra/`
6. Copy `.las` files to `Lidar_3D/`

### 2C — CloudCompare: Point Cloud Cleaning

1. Open `.las` file → Apply All → Yes to All
2. Set color to **Scalar Field → Classification**
3. Use **Filter by Value** (range 1–1.5) → Split into high/low elevation files
4. Work on the high-elevation file: use the **Scissor (Segmentation) tool** to isolate the embankment
5. Iteratively remove non-soil points (trees, houses, poles, birds)
   - Use `Alt + Left-click` to undo polygon points
   - Use `II` to pause/unpause during segmentation
6. Merge cleaned embankment file with low-elevation points
7. Repeat until the embankment is fully cleaned
8. Save final file as `.las` to `Intermediate/`

### 2D — CloudCompare → Raster DEM

1. Open cleaned `.las` file → segment to rectangular boundary
2. Run **Convert Cloud to 2D Raster** with settings:
   - Step: `0.5` (50 cm)
   - Active Layer: Cell Height Values
   - Direction: Z | Cell Height: Median
   - Empty Cells: Fill with **Kriging**
3. Update Grid → Export Raster → save to `DEM/` (e.g., `DEM_121`)
4. Generate **Hillshade** for visual QC

### 2E — ArcMap: Projection & Clipping

1. Add DEM raster → verify Spatial Reference is **undefined**
2. Define Projection: `WGS 1984 UTM Zone 45N`
3. Create a Polygon shapefile (`Drone_work`) in the same CRS
4. Draw polygon around embankment area using Editor
5. Create a File Geodatabase → run **Extract by Mask** (input: DEM, mask: `Drone_work`)
6. Export masked raster with `NoData = 0`

> Optional: Apply Hillshade with 70% transparency over clipped DEM for visualization.

---

## Step 3 — Elevation Correction & Segmentation

### 3A — Elevation Correction (R + ArcMap)

Script: `DEM_height_correction_manual.R`

- **Process 1:** Adjust DEMs to SRTM height reference
- **Process 2:** Polygon-based correction using RTK ground-truth points
- **Process 3:** Apply corrected elevation values to DEMs
- Move uncorrected and RTK-corrected DEMs to a folder named `Correction with overlap`

### 3B — DEM Mosaicking (ArcMap)

Script: `DEM_mosaic_and_gap_fill.R`

1. Run **Mosaic to New Raster** on all corrected DEMs
2. Fill NoData gaps using **Focal Statistics** (neighborhood fill)
3. Export final mosaic

### 3C — Cross-Section Generation (ArcMap)

1. Create embankment centerline → generate 100 m segments
2. Create perpendicular cross-section lines using the **ET GeoWizards** plugin
3. Draw four boundary lines: `Top_land`, `Toe_land`, `Top_river`, `Toe_river`
4. Use **Intersect** to generate intersection points per cross-section
5. Add XY coordinates to each point layer
6. Add and populate fields (e.g., `top_land_x`, `top_land_y`) using Field Calculator
7. Export each layer's attribute table to CSV:
   - `top_land.csv`, `toe_land.csv`, `top_river.csv`, `toe_river.csv`

### 3D — Elevation Statistics per Segment (RStudio)

Script: `Segment_data_analysis_stat summary.R`

Uses the four CSV files and the DEM mosaic to compute per-segment embankment statistics: height, width, land slope, river slope.

### 3E — Final Visualization (ArcMap)

1. Load `segment_stats_full_final.csv` as XY data
2. Export as shapefile: `segment_stats_points.shp`
3. Join with `embankment_100m_seg` on `Segment_ID`
4. Export joined layer as `embankment_segment_stats.shp`
5. Export final attribute table as `segment_stats_final.csv` using **Table to Table** tool

> **Note:** If columns are missing in the final shapefile due to field count limits, remove unnecessary columns from the CSV and re-run Step 3E from the beginning.

---

## Software Requirements

| Software | Purpose |
|---|---|
| DJI Terra | 2D ortho and 3D LiDAR reconstruction |
| CloudCompare | Point cloud classification and cleaning |
| ArcMap (ArcGIS Desktop) | Raster processing, projection, segmentation |
| RStudio | Elevation correction and statistical analysis |
| ET GeoWizards (ArcMap plugin) | Cross-section perpendicular line generation |

---

## R Scripts

| Script | Purpose |
|---|---|
| `DEM_height_correction_manual.R` | SRTM-based and RTK-based elevation correction |
| `DEM_mosaic_and_gap_fill.R` | DEM mosaicking and NoData filling |
| `Segment_data_analysis_stat summary.R` | Per-segment embankment statistics |

---

## Coordinate Reference System

All spatial outputs use: **WGS 1984 / UTM Zone 45N**

---

## Notes

- DJI Terra license is machine-locked; activate on the designated PC only
- Each Terra session auto-saves missions under `Documents/DJI/<gmail>/`
- CloudCompare segmentation is iterative — plan for multiple cleaning passes per grid
- Always verify RTK signal ("RTK Signal: Normal") before takeoff
