# SECOFS Transition to UFS-Coastal

This document outlines the steps required to transition SECOFS from the current nosofs/SCHISM workflow to UFS-Coastal with CDEPS DATM.

## Table of Contents

1. [Overview](#overview)
2. [Current nosofs vs UFS-Coastal Architecture](#current-nosofs-vs-ufs-coastal-architecture)
3. [File Comparison](#file-comparison)
4. [Variable Mapping](#variable-mapping)
5. [Grid Specifications](#grid-specifications)
6. [Transition Steps](#transition-steps)
7. [Static vs Cycle-Dependent Files](#static-vs-cycle-dependent-files)
8. [Script Locations & Usage](#script-locations--usage)
9. [Configuration Templates](#configuration-templates)
10. [Workflow Diagram](#workflow-diagram)

---

## Overview

### Current System (nosofs v3.7.0)
- **Ocean Model**: SCHISM (pschism_TVD-VL)
- **Atmospheric Forcing**: sflux files (nws=2)
- **Coupling**: Direct file read by SCHISM
- **Met Sources**: GFS (primary) + HRRR (secondary)

### Target System (UFS-Coastal)
- **Ocean Model**: SCHISM (via NUOPC cap)
- **Atmospheric Forcing**: CDEPS DATM
- **Coupling**: CMEPS mediator (NUOPC)
- **Met Sources**: GFS + HRRR via ESMF mesh

---

## Current nosofs vs UFS-Coastal Architecture

| Aspect | nosofs (SCHISM) | UFS-Coastal (DATM+SCHISM) |
|--------|-----------------|---------------------------|
| Executable | `pschism_TVD-VL` | `fv3.exe` (UFS driver) |
| Atm Forcing | sflux_*.nc files | ESMF mesh + DATM streams |
| Forcing Mode | nws=2 | nws=3 (NUOPC coupling) |
| Coupling | Direct file I/O | CMEPS mediator |
| Config Files | param.nml only | param.nml + ufs.configure + datm_in |

---

## File Comparison

### Files from nosofs Run (Reusable)

| File | Size | Purpose | UFS-Coastal Status |
|------|------|---------|-------------------|
| `hgrid.gr3` | 321 MB | SCHISM horizontal grid | Reuse as-is |
| `hgrid.ll` | 321 MB | Grid in lat/lon | Reuse as-is |
| `vgrid.in` | 1.6 GB | Vertical grid | Reuse as-is |
| `param.nml` | 37 KB | SCHISM parameters | Modify nws=3 |
| `bctides.in` | 1.5 MB | Tidal forcing | Reuse as-is |
| `elev2D.th.nc` | 9.7 MB | Elevation OBC | Reuse as-is |
| `TEM_3D.th.nc` | 14 MB | Temperature OBC | Reuse as-is |
| `SAL_3D.th.nc` | 14 MB | Salinity OBC | Reuse as-is |
| `uv3D.th.nc` | 29 MB | Velocity OBC | Reuse as-is |
| `*.gr3` files | Various | Property files | Reuse as-is |
| `hotstart.nc` | 18.6 GB | Restart file | Reuse as-is |

### sflux Files (Need Conversion)

| File | Grid | Variables | UFS-Coastal |
|------|------|-----------|-------------|
| `sflux_air_1.1.nc` | GFS 47×51 | uwind, vwind, prmsl, stmp, spfh | Convert to DATM format |
| `sflux_air_2.1.nc` | HRRR 745×630 | uwind, vwind, prmsl, stmp, spfh | Convert to DATM format |
| `sflux_rad_1.1.nc` | GFS 47×51 | dlwrf, dswrf | Convert to DATM format |
| `sflux_rad_2.1.nc` | HRRR 745×630 | dlwrf, dswrf | Convert to DATM format |
| `sflux_prc_1.1.nc` | GFS 47×51 | prate | Convert to DATM format |
| `sflux_prc_2.1.nc` | HRRR 745×630 | prate | Convert to DATM format |

### New Files Required for UFS-Coastal

| File | Purpose | Generator |
|------|---------|-----------|
| `gfs_esmf_mesh.nc` | GFS ESMF unstructured mesh | `nos_ofs_create_esmf_mesh.sh` |
| `hrrr_esmf_mesh.nc` | HRRR ESMF unstructured mesh | `nos_ofs_create_esmf_mesh.sh` |
| `gfs_datm.nc` | GFS data with DATM variable names | Converter script (TBD) |
| `hrrr_datm.nc` | HRRR data with DATM variable names | Converter script (TBD) |
| `datm_in` | DATM namelist | Template below |
| `datm.streams` | DATM stream configuration | Template below |
| `ufs.configure` | NEMS/NUOPC coupling config | Template below |
| `model_configure` | UFS model timing config | Template below |

---

## Variable Mapping

### sflux to DATM Variable Names

| sflux Variable | DATM Field | Standard Name | Units |
|----------------|------------|---------------|-------|
| `uwind` | `Sa_u10m` | eastward_wind | m/s |
| `vwind` | `Sa_v10m` | northward_wind | m/s |
| `prmsl` | `Sa_pslv` | air_pressure_at_sea_level | Pa |
| `stmp` | `Sa_tbot` | air_temperature | K |
| `spfh` | `Sa_shum` | specific_humidity | kg/kg |
| `dlwrf` | `Faxa_lwdn` | surface_downwelling_longwave_flux | W/m² |
| `dswrf` | `Faxa_swdn` | surface_downwelling_shortwave_flux | W/m² |
| `prate` | `Faxa_rain` | precipitation_flux | kg/m²/s |

### Coordinate Variable Names

| sflux | DATM |
|-------|------|
| `lon` | `longitude` |
| `lat` | `latitude` |
| `time` | `time` |

---

## Grid Specifications

### GFS Grid (0.25°)

| Parameter | nosofs (subsetted) | Full Global |
|-----------|-------------------|-------------|
| nx | 51 | 1440 |
| ny | 47 | 721 |
| Resolution | 0.25° | 0.25° |
| Lon range | -88° to -63° | 0° to 359.75° |
| Lat range | 17° to 40° | -90° to 90° |
| Grid type | Rectilinear | Rectilinear |

### HRRR Grid (3 km)

| Parameter | Value |
|-----------|-------|
| nx | 630 |
| ny | 745 |
| Resolution | ~3 km |
| Projection | Lambert Conformal |
| Grid type | Curvilinear |

### SECOFS Ocean Grid

| Parameter | Value |
|-----------|-------|
| Nodes | 1,684,786 |
| Elements | 3,322,329 |
| Vertical levels | 63 |
| Domain | US Southeast Coast |

---

## Transition Steps

### Phase 1: ESMF Mesh Generation (COMPLETED)

```bash
# Enable in secofs.ctl
export GENERATE_ESMF_MESH=true

# Or run standalone
./nos_ofs_create_esmf_mesh.sh GFS25 gfs.grib2 ./output
./nos_ofs_create_esmf_mesh.sh HRRR hrrr.grib2 ./output
```

**Output files:**
- `gfs_esmf_mesh.nc` (~600 KB for subsetted, ~66 MB for full)
- `hrrr_esmf_mesh.nc` (~29 MB)

### Phase 2: Data Conversion (NOT NEEDED)

**Clarification:** Separate data conversion is NOT required because:
1. Existing scripts (`nos_ofs_create_esmf_mesh.sh`) generate `*_for_esmf.nc` files
2. DATM handles variable name mapping in `datm.streams` configuration
3. The `stream_data_variables` directive maps source names to DATM field names

Example mapping in datm.streams:
```
stream_data_variables01:
  "UGRD_10maboveground     Sa_u10m"
  "VGRD_10maboveground     Sa_v10m"
  "TMP_2maboveground       Sa_tbot"
```

### Phase 3: Configuration Files (COMPLETED)

Template files created in `FIXofs/secofs/`:

| File | Type | Purpose |
|------|------|---------|
| `ufs.configure` | Static | NUOPC coupling configuration |
| `model_configure.template` | Template | Model timing (start time, forecast length) |
| `datm_in.template` | Template | DATM namelist |
| `datm.streams.template` | Template | Stream definitions with variable mapping |

**Helper script:** `ush/nos_ofs_gen_ufs_config.sh`

```bash
# Generate runtime configs from templates
export PDY=20251231
export cyc=06
export DATA=/path/to/working/dir
export FIXofs=/path/to/fix/secofs

./nos_ofs_gen_ufs_config.sh -v
```

**Template placeholders:**
- `@[YYYY]`, `@[MM]`, `@[DD]`, `@[HH]` - Date/time components
- `@[DATA]` - Working directory path
- `@[NHOURS]` - Forecast length
- `@[DT_ATMOS]` - Atmospheric coupling timestep

### Phase 4: param.nml Modification

```fortran
! Change from:
nws = 2  ! sflux file input

! To:
nws = 3  ! NUOPC coupling with DATM
```

### Phase 5: Testing

1. Run short simulation (6 hours)
2. Compare outputs with nosofs baseline
3. Validate forcing fields at model interface
4. Check conservation properties

---

## Static vs Cycle-Dependent Files

Understanding which files are static (generate once) vs cycle-dependent (regenerate each forecast cycle) is critical for operational efficiency.

### Static Files (Generate Once, Cache in FIXofs)

These files depend only on grid geometry, not on forecast time:

| File | Purpose | Notes |
|------|---------|-------|
| `gfs_esmf_mesh.nc` | GFS 0.25° ESMF mesh | Grid geometry only |
| `hrrr_esmf_mesh.nc` | HRRR 3km ESMF mesh | Grid geometry only |
| `schism_esmf_mesh.nc` | SCHISM unstructured mesh | From hgrid.gr3 |
| `ufs.configure` | NUOPC coupling config | Component connections |
| `nems.configure` | NEMS component config | If using NEMS driver |
| `fd_nems.yaml` | Field dictionary | Variable definitions |

**SCHISM grid files** (already in FIXofs):
- `hgrid.gr3`, `hgrid.ll`
- `vgrid.in`
- `bctides.in_template`
- `*.gr3` (drag, manning, albedo, etc.)

### Cycle-Dependent Files (Regenerate Each Cycle)

These files contain time-varying data or time-specific settings:

| File | Purpose | What Changes |
|------|---------|--------------|
| `gfs_for_esmf.nc` | GFS atmospheric data | New forecast data |
| `hrrr_for_esmf.nc` | HRRR atmospheric data | New forecast data |
| `model_configure` | Model timing | `start_year/month/day/hour`, `nhours_fcst` |
| `datm_in` | DATM namelist | `model_meshfile`, stream file paths |
| `datm.streams` | Stream definitions | `yearFirst`, `yearLast`, data file paths |
| `bctides.in` | Tidal forcing | Nodal factors for specific date |
| `hotstart.nc` | Initial conditions | From previous cycle |
| OBC files | Boundary conditions | RTOFS data for cycle |
| River forcing | NWM/USGS data | River discharge for cycle |

### Template Approach for Cycle-Dependent Config Files

For operational efficiency, create templates with placeholders:

**model_configure.template**:
```
start_year:  @[YYYY]
start_month: @[MM]
start_day:   @[DD]
start_hour:  @[HH]
nhours_fcst: @[FCST_LEN]
```

**datm.streams.template**:
```xml
<stream datasource="GFS">
  <yearFirst>@[YYYY]</yearFirst>
  <yearLast>@[YYYY]</yearLast>
  <dataFile>@[COMOUT]/gfs_for_esmf.nc</dataFile>
</stream>
```

Then use `sed` or `envsubst` at runtime to substitute values:

```bash
# Example using sed
sed -e "s/@\[YYYY\]/${PDY:0:4}/g" \
    -e "s/@\[MM\]/${PDY:4:2}/g" \
    -e "s/@\[DD\]/${PDY:6:2}/g" \
    -e "s/@\[HH\]/${cyc}/g" \
    -e "s/@\[FCST_LEN\]/${LEN_FORECAST}/g" \
    model_configure.template > model_configure
```

### Recommended Directory Structure

```
FIXofs/secofs/
├── gfs_esmf_mesh.nc        (static - generate once)
├── hrrr_esmf_mesh.nc       (static - generate once)
├── schism_esmf_mesh.nc     (static - generate once)
├── ufs.configure           (static)
├── model_configure.template
├── datm_in.template
├── datm.streams.template
└── [existing SCHISM fix files]

$DATA/ (cycle-specific working directory)
├── gfs_for_esmf.nc         (generated by nos_ofs_create_forcing_met.sh)
├── hrrr_for_esmf.nc        (generated by nos_ofs_create_forcing_met.sh)
├── model_configure         (from template + sed)
├── datm_in                 (from template + sed)
├── datm.streams            (from template + sed)
└── [model output files]
```

### Generation Timing

| File Type | When to Generate | How Often |
|-----------|-----------------|-----------|
| ESMF mesh files | Initial deployment or grid change | Once per grid version |
| `ufs.configure` | Initial deployment | Once (unless coupling changes) |
| Config templates | Initial deployment | Once (update as needed) |
| Atmospheric data | Each prep stage | Every cycle (4x daily) |
| Runtime configs | Each prep stage | Every cycle (4x daily) |
| OBC/River data | Each prep stage | Every cycle (4x daily) |

---

## Script Locations & Usage

### Directory Structure

```
nosofs.v3.7.0/
├── ush/
│   ├── nos_ofs_create_esmf_mesh.sh    # ESMF mesh generation wrapper
│   ├── nos_ofs_gen_ufs_config.sh      # UFS config file generator
│   ├── nos_ofs_create_forcing_met.sh  # Main met forcing (integrates both above)
│   └── pysh/
│       ├── proc_scrip.py              # SCRIP grid generator (Python)
│       ├── modify_gfs_4_esmfmesh.py   # GFS CF-compliance modifier
│       └── modify_hrrr_4_esmfmesh.py  # HRRR CF-compliance modifier
└── fix/secofs/
    ├── secofs.ctl                     # Control file (set GENERATE_ESMF_MESH=true)
    ├── ufs.configure                  # Static NUOPC coupling config
    ├── model_configure.template       # Model timing template
    ├── datm_in.template               # DATM namelist template
    └── datm.streams.template          # Stream configuration template
```

### How to Run

#### Option 1: Through nosofs Workflow (Recommended for Operations)

Enable UFS file generation in `secofs.ctl`:

```bash
# In fix/secofs/secofs.ctl
export GENERATE_ESMF_MESH=true
```

Then run the normal prep stage. The workflow will automatically:
1. Generate sflux files (existing functionality)
2. Generate ESMF mesh files (`gfs_esmf_mesh.nc`, `hrrr_esmf_mesh.nc`)
3. Generate UFS config files (`model_configure`, `datm_in`, `datm.streams`, `ufs.configure`)

#### Option 2: Standalone ESMF Mesh Generation

```bash
# Set environment
export USHnos=/path/to/nosofs.v3.7.0/ush
export WGRIB2=/path/to/wgrib2
export ESMF_SCRIP2UNSTRUCT=/path/to/ESMF_Scrip2Unstruct

# Generate GFS mesh
${USHnos}/nos_ofs_create_esmf_mesh.sh GFS25 /path/to/gfs.t06z.pgrb2.0p25.f000 ./output

# Generate HRRR mesh
${USHnos}/nos_ofs_create_esmf_mesh.sh HRRR /path/to/hrrr.t06z.wrfsfcf00.grib2 ./output
```

**Output files:**
- `gfs_for_esmf.nc` - GFS data with CF attributes
- `gfs_scrip.nc` - Intermediate SCRIP format
- `gfs_esmf_mesh.nc` - Final ESMF unstructured mesh
- (Same pattern for HRRR)

#### Option 3: Standalone UFS Config Generation

```bash
# Set required environment variables
export PDY=20251231                    # Forecast date (YYYYMMDD)
export cyc=06                          # Cycle hour (00, 06, 12, 18)
export DATA=/path/to/working/dir       # Working directory
export FIXofs=/path/to/fix/secofs      # Template directory

# Optional environment variables
export NHOURS=48                       # Forecast length (default: 48)
export DT_ATMOS=120                    # Coupling timestep (default: 120)
export USE_HRRR=true                   # Include HRRR stream (default: true)

# Create working directory
mkdir -p $DATA/INPUT

# Run config generator
/path/to/nosofs.v3.7.0/ush/nos_ofs_gen_ufs_config.sh -v
```

**Output files in $DATA/:**
- `model_configure` - Model timing configuration
- `datm_in` - DATM Fortran namelist
- `datm.streams` - Stream definitions with variable mapping
- `ufs.configure` - NUOPC coupling configuration
- `INPUT/` - Directory for mesh and data files

### Output Files Summary

When `GENERATE_ESMF_MESH=true`, the workflow produces:

| File | Location | Purpose |
|------|----------|---------|
| `gfs_esmf_mesh.nc` | `$DATA/INPUT/` & `$COMOUT/` | GFS ESMF unstructured mesh |
| `hrrr_esmf_mesh.nc` | `$DATA/INPUT/` & `$COMOUT/` | HRRR ESMF unstructured mesh |
| `gfs_for_esmf.nc` | `$DATA/INPUT/` | GFS atmospheric data (CF-compliant) |
| `hrrr_for_esmf.nc` | `$DATA/INPUT/` | HRRR atmospheric data (CF-compliant) |
| `model_configure` | `$DATA/` & `$COMOUT/` | UFS model timing settings |
| `datm_in` | `$DATA/` & `$COMOUT/` | DATM namelist |
| `datm.streams` | `$DATA/` & `$COMOUT/` | DATM stream configuration |
| `ufs.configure` | `$DATA/` & `$COMOUT/` | NUOPC/CMEPS coupling config |

### Environment Variables Reference

#### Required Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `PDY` | `20251231` | Forecast date (YYYYMMDD) |
| `cyc` | `06` | Cycle hour (00, 06, 12, 18) |
| `DATA` | `/lfs/h1/ops/tmp/secofs.20251231` | Working directory |
| `FIXofs` | `/lfs/h1/ops/nosofs/fix/secofs` | Fix files directory |

#### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NHOURS` | `48` | Forecast length in hours |
| `DT_ATMOS` | `120` | Atmospheric coupling timestep (seconds) |
| `NX_GFS` | `101` | GFS grid x-dimension (SECOFS subset) |
| `NY_GFS` | `93` | GFS grid y-dimension (SECOFS subset) |
| `USE_HRRR` | `true` | Include HRRR stream in datm.streams |
| `GENERATE_ESMF_MESH` | `false` | Enable ESMF/UFS file generation |
| `GENERATE_UFS_CONFIG` | `true` | Generate UFS config files (when ESMF enabled) |

### Dependencies

| Tool | Purpose | Module (WCOSS2) |
|------|---------|-----------------|
| `wgrib2` | GRIB2 to NetCDF conversion | `wgrib2` |
| `ESMF_Scrip2Unstruct` | SCRIP to ESMF mesh conversion | `esmf` |
| `python3` | Python scripts execution | `python/3.x` |
| `netCDF4` | Python NetCDF library | `python/3.x` |
| `xarray` | Python data arrays | `pip install xarray` |
| `numpy` | Python numerical library | `python/3.x` |

### Workflow Integration Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     nos_ofs_create_forcing_met.sh                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  [Existing sflux generation]                                            │
│           │                                                             │
│           ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  if GENERATE_ESMF_MESH=true && OCEAN_MODEL=SCHISM               │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  1. nos_ofs_create_esmf_mesh.sh GFS25                           │   │
│  │     ├── wgrib2 (extract variables)                              │   │
│  │     ├── modify_gfs_4_esmfmesh.py (CF attributes)                │   │
│  │     ├── proc_scrip.py (SCRIP grid)                              │   │
│  │     └── ESMF_Scrip2Unstruct (ESMF mesh)                         │   │
│  │                                                                  │   │
│  │  2. nos_ofs_create_esmf_mesh.sh HRRR                            │   │
│  │     └── (same steps as GFS)                                     │   │
│  │                                                                  │   │
│  │  3. nos_ofs_gen_ufs_config.sh                                   │   │
│  │     ├── sed model_configure.template → model_configure          │   │
│  │     ├── sed datm_in.template → datm_in                          │   │
│  │     ├── sed datm.streams.template → datm.streams                │   │
│  │     └── cp ufs.configure → $DATA/                               │   │
│  │                                                                  │   │
│  │  4. Copy outputs to $COMOUT                                     │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Configuration Templates

### datm_in (DATM Namelist)

```fortran
&datm_nml
  datamode = "ATMMESH"
  factorfn_data = "null"
  factorfn_mesh = "null"
  flds_co2 = .false.
  flds_presaero = .false.
  flds_wiso = .false.
  iradsw = 1
  model_maskfile = "INPUT/gfs_esmf_mesh.nc"
  model_meshfile = "INPUT/gfs_esmf_mesh.nc"
  nx_global = 51
  ny_global = 47
  restfilm = "null"
  export_all = .true.
/
```

### datm.streams (Stream Configuration)

```
! GFS Stream
stream_info:               gfs.01
taxmode01:                 limit
mapalgo01:                 redist
tInterpAlgo01:             linear
readMode01:                single
dtlimit01:                 1.5
stream_offset01:           0
yearFirst01:               2025
yearLast01:                2025
yearAlign01:               2025
stream_vectors01:          null
stream_mesh_file01:        "INPUT/gfs_esmf_mesh.nc"
stream_lev_dimname01:      null
stream_data_files01:       "INPUT/gfs_datm.nc"
stream_data_variables01:   "Sa_u10m Sa_u10m" "Sa_v10m Sa_v10m" "Sa_pslv Sa_pslv" "Sa_tbot Sa_tbot" "Sa_shum Sa_shum" "Faxa_lwdn Faxa_lwdn" "Faxa_swdn Faxa_swdn" "Faxa_rain Faxa_rain"

! HRRR Stream (higher priority for CONUS)
stream_info:               hrrr.02
taxmode02:                 limit
mapalgo02:                 redist
tInterpAlgo02:             linear
readMode02:                single
dtlimit02:                 1.5
stream_offset02:           0
yearFirst02:               2025
yearLast02:                2025
yearAlign02:               2025
stream_vectors02:          null
stream_mesh_file02:        "INPUT/hrrr_esmf_mesh.nc"
stream_lev_dimname02:      null
stream_data_files02:       "INPUT/hrrr_datm.nc"
stream_data_variables02:   "Sa_u10m Sa_u10m" "Sa_v10m Sa_v10m" "Sa_pslv Sa_pslv" "Sa_tbot Sa_tbot" "Sa_shum Sa_shum" "Faxa_lwdn Faxa_lwdn" "Faxa_swdn Faxa_swdn" "Faxa_rain Faxa_rain"
```

### ufs.configure (NUOPC Coupling)

```
#############################################
####  NEMS Run-Time Configuration File  #####
#############################################

# ESMF #
logKindFlag:            ESMF_LOGKIND_MULTI
globalResourceControl:  true

# EARTH #
EARTH_component_list: ATM OCN MED
EARTH_attributes::
  Verbosity = 0
::

# MED (CMEPS Mediator) #
MED_model:                      cmeps
MED_petlist_bounds:             0 119
MED_omp_num_threads:            1
MED_attributes::
  ATM_model = datm
  OCN_model = schism
  history_n = 1
  history_option = nhours
  history_ymd = -999
  coupling_mode = coastal
::

# ATM (DATM) #
ATM_model:                      datm
ATM_petlist_bounds:             0 119
ATM_omp_num_threads:            1
ATM_attributes::
  Verbosity = 0
  DumpFields = false
  ProfileMemory = false
  OverwriteSlice = true
::

# OCN (SCHISM) #
OCN_model:                      schism
OCN_petlist_bounds:             120 1319
OCN_omp_num_threads:            1
OCN_attributes::
  Verbosity = 0
  DumpFields = false
  ProfileMemory = false
  OverwriteSlice = true
  meshloc = element
  CouplingConfig = none
::

# Run Sequence #
runSeq::
@1800
  ATM -> MED :remapMethod=redist
  MED med_phases_post_atm
  OCN -> MED :remapMethod=redist
  MED med_phases_post_ocn
  MED med_phases_prep_atm
  MED med_phases_prep_ocn_accum
  MED med_phases_prep_ocn_avg
  MED -> ATM :remapMethod=redist
  MED -> OCN :remapMethod=redist
  ATM
  OCN
  MED med_phases_history_write
  MED med_phases_restart_write
@
::

ALLCOMP_attributes::
  ScalarFieldCount = 3
  ScalarFieldIdxGridNX = 1
  ScalarFieldIdxGridNY = 2
  ScalarFieldIdxNextSwCday = 3
  ScalarFieldName = cpl_scalars
  start_type = startup
  restart_dir = RESTART/
  case_name = secofs.cpld
  restart_n = 6
  restart_option = nhours
  restart_ymd = -999
  orb_eccen = 1.e36
  orb_iyear = 2000
  orb_iyear_align = 2000
  orb_mode = fixed_year
  orb_mvelp = 1.e36
  orb_obliq = 1.e36
  stop_n = 48
  stop_option = nhours
  stop_ymd = -999
::
```

### model_configure

```
start_year:              2025
start_month:             12
start_day:               31
start_hour:              06
start_minute:            0
start_second:            0
nhours_fcst:             48
fhrot:                   0

dt_atmos:                120
restart_interval:        6
quilting:                .true.
write_groups:            1
write_tasks_per_group:   6
output_history:          .true.
write_dopost:            .false.
num_files:               2
filename_base:           'atm' 'sfc'
output_grid:             'regional_latlon'
output_file:             'netcdf'
imo:                     101
jmo:                     93
```

---

## Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SECOFS UFS-Coastal Workflow                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      PREP STAGE                                  │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │  GFS GRIB2 ──┬──> sflux_air_1.nc ──┐                            │   │
│  │              ├──> sflux_rad_1.nc ──┼──> gfs_datm.nc             │   │
│  │              ├──> sflux_prc_1.nc ──┘         │                   │   │
│  │              │                               │                   │   │
│  │              └──> gfs_esmf_mesh.nc ──────────┼──> INPUT/         │   │
│  │                                              │                   │   │
│  │  HRRR GRIB2 ─┬──> sflux_air_2.nc ──┐        │                   │   │
│  │              ├──> sflux_rad_2.nc ──┼──> hrrr_datm.nc            │   │
│  │              ├──> sflux_prc_2.nc ──┘         │                   │   │
│  │              │                               │                   │   │
│  │              └──> hrrr_esmf_mesh.nc ─────────┘                   │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      RUN STAGE                                   │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                  │   │
│  │   INPUT/                                                         │   │
│  │   ├── gfs_esmf_mesh.nc                                          │   │
│  │   ├── hrrr_esmf_mesh.nc                                         │   │
│  │   ├── gfs_datm.nc          ┌─────────────────┐                  │   │
│  │   └── hrrr_datm.nc    ───> │     DATM        │                  │   │
│  │                             │  (Atmosphere)   │                  │   │
│  │   datm_in                   └────────┬────────┘                  │   │
│  │   datm.streams                       │                           │   │
│  │                                      ▼                           │   │
│  │                             ┌─────────────────┐                  │   │
│  │   ufs.configure        ───> │     CMEPS       │                  │   │
│  │   model_configure           │   (Mediator)    │                  │   │
│  │                             └────────┬────────┘                  │   │
│  │                                      │                           │   │
│  │   hgrid.gr3                          ▼                           │   │
│  │   vgrid.in              ┌─────────────────┐                      │   │
│  │   param.nml (nws=3) ──> │     SCHISM      │ ──> outputs/        │   │
│  │   bctides.in            │    (Ocean)      │     ├── out2d_*.nc  │   │
│  │   *_3D.th.nc            └─────────────────┘     ├── salinity_*.nc│   │
│  │   hotstart.nc                                   └── ...          │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## References

- [UFS-Coastal Documentation](https://ufs-coastal.readthedocs.io/)
- [CDEPS DATM Guide](https://escomp.github.io/CDEPS/versions/master/html/datm.html)
- [ESMF Reference Manual](https://earthsystemmodeling.org/docs/release/latest/ESMF_refdoc/)
- [SCHISM Manual](http://ccrm.vims.edu/schismweb/SCHISM_v5.10-Manual.pdf)

---

## Document History

| Date | Version | Author | Description |
|------|---------|--------|-------------|
| 2026-01-03 | 1.0 | Claude Code | Initial draft |
| 2026-01-03 | 1.1 | Claude Code | Added Static vs Cycle-Dependent Files section |
| 2026-01-03 | 1.2 | Claude Code | Added UFS config templates (Phase 3 complete) |
| 2026-01-03 | 1.3 | Claude Code | Added Script Locations & Usage section |

---

*Created for SECOFS UFS-Coastal transition project*
