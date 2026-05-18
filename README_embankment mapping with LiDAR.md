# Embankment Mapping with LiDAR

[![Language](https://img.shields.io/badge/Language-R-276DC3?logo=r)](https://www.r-project.org/)
[![Platform](https://img.shields.io/badge/Platform-DJI%20Terra%20%7C%20CloudCompare%20%7C%20ArcGIS-lightgrey)](.)
[![Data](https://img.shields.io/badge/Data-LiDAR%20%7C%20RTK%20GNSS%20%7C%20SRTM-green)](.)
[![Segments](https://img.shields.io/badge/Output-4%2C224%20segments-blue)](.)
[![License](https://img.shields.io/badge/License-Academic%20Use-yellow)](.)

---

## Overview

River embankments are critical flood-protection infrastructure. Yet systematically measuring their condition — height, width, slope — across tens of kilometres is rarely feasible with traditional survey methods.

This project builds a complete, reproducible pipeline to do exactly that. Starting from raw drone imagery and LiDAR point clouds captured in the field, it produces a spatially referenced database of **4,224 embankment segments** at 100-metre intervals, each with statistics on DEM elevation, crest width, river-side slope, and land-side slope. The pipeline runs from drone deployment to analysis-ready CSV and shapefile, and is documented end-to-end in an accompanying field and processing manual.

---

## Study Area

**Southwestern Bangladesh** — a low-lying coastal delta where embankments (locally called *polders*) are the primary defence against tidal flooding and cyclone surge. Survey grids were flown using a DJI drone with an L2 LiDAR sensor and RTK base station. The coordinate system used throughout is **WGS84 / UTM Zone 45N**.

---

## Pipeline at a Glance

```
Field (drone + RTK)
        │
        ▼
DJI Terra ──► Orthomosaic + LiDAR Point Cloud
        │
        ▼
CloudCompare ──► Ground Classification + DEM Export (50 cm)
        │
        ▼
ArcMap ──► Projection, Clipping, Mosaic
        │
        ▼
R (DEM_height_correction_manual.R)
  ├─ Process 1: SRTM-based height correction (median dZ, outlier trimming)
  ├─ Process 2: Polygon footprint creation per DEM tile
  ├─ Process 3: RTK ground-truth correction (per-tile median offset)
  └─ Process 4: Overlap-based correction for tiles without RTK coverage
        │
        ▼
ArcGIS (ET GeoWizards) ──► 100m segments + perpendicular cross-sections
        │
        ▼
R (Segment_data_analysis_stat_summary.R)
  ├─ Join: river top / river toe / land top / land toe intersect points
  ├─ Compute: width, vertical distances, slope (% and °), horizontal distances
  ├─ Filter: noise removal (min thresholds)
  ├─ Summarise: mean, median, P20, P80, min, max, SD per segment
  └─ Gap-fill: 7-point moving average for missing segments
        │
        ▼
Output: Embankment_100m_segment_database (.csv)
```

---

## Repository Structure

```
Embankment_mapping_with_LiDAR/
├── code/
│   ├── DEM_height_correction_manual.R         # Processes 1–4: elevation correction
│   └── Segment_data_analysis_stat_summary.R   # Cross-section stats and segment database
├── data/
│   ├── Embankment_100m_segment_database.csv   # Final output — 4,224 segments
│   └── shapefile/
│       ├── Embankment_100m_segment_database.shp
│       ├── Embankment_100m_segment_database.dbf
│       ├── Embankment_100m_segment_database.shx
│       ├── Embankment_100m_segment_database.prj
│       ├── Embankment_100m_segment_database.sbn
│       ├── Embankment_100m_segment_database.sbx
│       └── Embankment_100m_segment_database.cpg
└── docs/
    └── Drone_survey_and_data_processing_Manual_Mahima.docx   # Full field + processing manual
```

---

## Output Dataset

The final database (`Embankment_100m_segment_database`) contains **4,224 georeferenced segments**. Each row represents one 100-metre embankment segment with the following fields:

| Field group | Columns | Description |
|---|---|---|
| Location | `Long`, `Lat` | Segment centroid coordinates |
| Identity | `Segment`, `seg_length` | Segment ID and cumulative length |
| DEM elevation | `DEM_mean`, `DEM_median`, `DEM_p20`, `DEM_p80`, `DEM_min`, `DEM_max`, `DEM_sd` | Elevation statistics from the corrected DEM (metres) |
| Crest width | `width_mean`, `width_median`, `width_p20`, `width_p80`, `width_min`, `width_max`, `width_sd` | Euclidean distance between land-top and river-top boundary (metres) |
| River-side slope | `river_mean`, `river_medi`, `river_p20`, `river_p80`, `river_min`, `river_max` | Slope angle toward the river (degrees) |
| Land-side slope | `land_mean`, `land_media`, `land_p20`, `land_p80`, `land_min`, `land_max` | Slope angle toward the land (degrees) |
| Data quality | `averaged`, `n` | Flags gap-filled segments; count of valid cross-sections |

**Summary statistics (DEM elevation, metres):**

| Metric | Value |
|---|---|
| Median | 3.51 m |
| 25th percentile | 3.18 m |
| 75th percentile | 3.90 m |
| Max | 7.35 m |

---

## R Scripts

### `DEM_height_correction_manual.R`

Corrects elevation offsets across multiple LiDAR-derived DEM tiles using three sequential methods:

1. **SRTM correction** — resamples a SRTM-modelled DEM to each tile, trims the top 25% of elevation values (removes embankment features), and applies the median difference as a flat offset
2. **RTK correction** — uses centimetre-accurate ground control points to apply a per-tile median correction on top of the SRTM-corrected DEMs
3. **Overlap correction** — for tiles without RTK coverage, identifies spatially overlapping RTK-corrected tiles, randomly samples 50 overlap points, and applies the median dZ correction

**Dependencies:** `terra`, `sf`

### `Segment_data_analysis_stat_summary.R`

Reads four intersection point files (river top, river toe, land top, land toe) extracted from ArcGIS cross-sections, joins them, and computes per-cross-section geometry:

- **Width** — Euclidean distance between land-top and river-top coordinates
- **Vertical distances** — DEM height difference between top and toe on each side
- **Horizontal distances** — projected base distance for slope calculation
- **Slopes** — both in degrees and percentage, for river and land sides

Cross-sections failing minimum-quality thresholds (horizontal distance < 0.25 m, vertical distance < 0.25 m, width < 0.5 m) are removed. Remaining cross-sections are grouped by segment and summarised (mean, median, P20, P80, min, max, SD). Missing segments are gap-filled using a 7-point centred moving average.

**Dependencies:** `dplyr`, `zoo`

---

## How to Run

### Prerequisites

```r
install.packages(c("terra", "sf", "dplyr", "zoo"))
```

### Steps

1. Update the folder paths in each script to point to your local DEM and data directories (currently set to network paths used during the survey program)
2. Run `DEM_height_correction_manual.R` — outputs SRTM-corrected and RTK-corrected GeoTIFFs
3. Generate 100m segment lines, perpendicular cross-sections, and intersection points in ArcGIS / ET GeoWizards (see `docs/` manual, RStudio Processing section)
4. Run `Segment_data_analysis_stat_summary.R` with the intersection CSVs as input — outputs `segment_stats_full_final.csv`
5. Join the stats table back to the segment shapefile in ArcGIS for the final spatial database

---

## Documentation

The file `docs/Drone_survey_and_data_processing_Manual_Mahima.docx` is a step-by-step processing manual covering:

- DJI drone field operations and flight planning (L2 LiDAR, RTK base station)
- LiDAR point cloud reconstruction and 2D orthomosaic generation in DJI Terra
- Ground classification, DEM generation, and contour extraction
- Point cloud cleaning in CloudCompare (vegetation, structure, and noise removal)
- DEM rasterisation, projection, and mosaicking in ArcMap
- Cross-section generation using ET GeoWizards
- Full RStudio processing workflow (elevation correction → segment statistics)

---

## Tools Used

| Tool | Purpose |
|---|---|
| DJI Terra | Point cloud reconstruction, orthomosaic generation |
| CloudCompare | Ground classification, DEM export |
| ArcMap (ArcGIS Desktop) | Projection, mosaicking, cross-section analysis |
| ET GeoWizards | Automated perpendicular cross-section generation |
| RStudio (R) | Elevation correction, segment statistics |
| RTK GNSS | Centimetre-level ground control |

---

## Citation

If you use the data, scripts, or methodology from this repository, please cite:

> Tarana, M. (2025). *Embankment Mapping with LiDAR: A Drone-Based Survey and Processing Pipeline for River Embankment Condition Assessment*. GitHub repository: https://github.com/mahimatarana/Embankment_mapping_with_LiDAR

---

## License

This repository is shared for academic and research purposes. Please contact the author before reproducing or adapting the data, code, or documentation for other uses.
