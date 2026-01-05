# NOSOFS UFS-Coastal Integration

This repository contains scripts and configurations for integrating NOAA's Operational Ocean Forecast Systems (NOS-OFS) with UFS-Coastal.

## Overview

Transitioning NOS-OFS models from standalone SCHISM to UFS-Coastal coupled framework using CDEPS/NUOPC for atmosphere-ocean coupling.

**Current Focus:** SECOFS (Southeast Coastal Ocean Forecast System)

## Key Components

| Directory | Contents |
|-----------|----------|
| `ush/` | Utility scripts for DATM forcing and ESMF mesh generation |
| `fix/secofs/` | Control files and UFS configuration templates |
| `jobs/` | J-job scripts for WCOSS2 |
| `scripts/` | Ex-scripts for prep, nowcast, forecast |
| `ecf/` | ECF job card templates |

## UFS-Coastal DATM Workflow

```
GFS/HRRR GRIB2 → ESMF Mesh → DATM Forcing → NUOPC Coupler → SCHISM
```

Key scripts:
- `nos_ofs_create_esmf_mesh.sh` - Generate ESMF mesh files
- `nos_ofs_create_datm_forcing.sh` - Create DATM forcing files
- `nos_ofs_gen_ufs_config.sh` - Generate UFS configuration

## Requirements

- wgrib2, NCO tools
- ESMF (for `ESMF_Scrip2Unstruct`)
- Python 3 with netCDF4, numpy, xarray

## Related

- [UFS-Coastal](https://github.com/ufs-community/ufs-coastal)
- [CDEPS](https://github.com/ESCOMP/CDEPS)
