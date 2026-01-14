# UFS-NOS-OFS

UFS-Coastal Integration for NOAA's National Ocean Service Operational Forecast Systems (NOS-OFS).

## Overview

This repository contains scripts and configurations for transitioning NOS-OFS models from standalone ocean models (SCHISM, FVCOM, ROMS) to the UFS-Coastal coupled framework using CDEPS/NUOPC for atmosphere-ocean coupling.

**Current Focus:** SECOFS (Southeast Coastal Ocean Forecast System)

**Future Extensions:** CBOFS, DBOFS, TBOFS, GOMOFS, and other NOS-OFS systems

## Key Components

| Directory | Contents |
|-----------|----------|
| `ush/` | Utility scripts for DATM forcing, ESMF mesh, and HRRR+GFS blending |
| `fix/secofs/` | Control files and UFS configuration templates |
| `jobs/` | J-job scripts for WCOSS2 |
| `scripts/` | Ex-scripts for prep, nowcast, forecast |
| `ecf/` | ECF job card templates |

## UFS-Coastal DATM Workflow

```
HRRR (3km) ─┐
            ├─► Blending ─► ESMF Mesh ─► DATM ─► NUOPC Coupler ─► SCHISM
GFS (25km) ─┘
```

### Key Scripts

| Script | Purpose |
|--------|---------|
| `nos_ofs_blend_hrrr_gfs.sh` | Blend HRRR (CONUS) + GFS (Caribbean/PR) |
| `nos_ofs_create_datm_forcing.sh` | Create DATM forcing files |
| `nos_ofs_create_datm_forcing_blended.sh` | Wrapper for blended forcing generation |
| `nos_ofs_create_esmf_mesh.sh` | Generate ESMF mesh files |

### DATM Blending Configuration

Enable in `secofs.ctl`:
```bash
export USE_DATM=1              # Enable DATM forcing
export DATM_BLEND_HRRR_GFS=1   # Enable HRRR+GFS blending
export DATM_DOMAIN=SECOFS      # Domain: SECOFS, ATLANTIC, STOFS3D_ATL
```

## Requirements

- wgrib2, NCO tools
- ESMF (for `ESMF_Scrip2Unstruct`)
- Python 3 with numpy, netCDF4, scipy

## Related Projects

- [UFS-Coastal](https://github.com/oceanmodeling/ufs-weather-model)
- [CDEPS](https://github.com/ESCOMP/CDEPS)
- [SCHISM](https://github.com/schism-dev/schism)

## Disclaimer

The United States Department of Commerce (DOC) GitHub project code is provided on an "as is" basis and the user assumes responsibility for its use. DOC has relinquished control of the information and no longer has responsibility to protect the integrity, confidentiality, or availability of the information. Any claims against the Department of Commerce stemming from the use of its GitHub project will be governed by all applicable Federal law. Any reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise, does not constitute or imply their endorsement, recommendation or favoring by the Department of Commerce. The Department of Commerce seal and logo, or the seal and logo of a DOC bureau, shall not be used in any manner to imply endorsement of any commercial product or activity by DOC or the United States Government.
