#!/bin/bash
# =============================================================================
# Test Script: Validate DATM file selection logic
#
# Purpose: Dry-run test to verify the file selection logic matches Machuan's
#          approach. Shows what files WOULD be selected without needing data.
#
# Usage: ./test_datm_file_selection.sh
# =============================================================================

set -e

echo "============================================"
echo "DATM File Selection Logic Test"
echo "============================================"

# Simulated run parameters (matching Machuan's 00Z run)
PDY=20241225
cyc=00
TIME_HOTSTART="${PDY}00"
TIME_START=$(date -d "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00 - 6 hours" +%Y%m%d%H 2>/dev/null || echo "2024122418")
TIME_FORECAST_END=$(date -d "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00 + 48 hours" +%Y%m%d%H 2>/dev/null || echo "2024122700")

echo ""
echo "Run Configuration:"
echo "  PDY:            $PDY"
echo "  cyc:            $cyc"
echo "  TIME_START:     $TIME_START (nowcast begins)"
echo "  TIME_END:       $TIME_FORECAST_END (forecast ends)"
echo ""

# =============================================================================
# Expected GFS file selection (based on Machuan's logs)
# =============================================================================
echo "============================================"
echo "Expected GFS Files (from Machuan's approach)"
echo "============================================"
echo ""
echo "Base cycle: gfs.t18z from $(date -d "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} - 1 day" +%Y%m%d 2>/dev/null || echo "20241224")"
echo ""

# GFS uses 3-hourly intervals
# For 00Z run with nowcast starting at 18Z (6h back), forecast ending at 00Z+48h
# We need valid times: 18Z, 21Z, 00Z, 03Z, 06Z, ... through 00Z+48h

# Show expected GFS files
GFS_CYCLE_DATE="20241224"  # Previous day
GFS_CYCLE="18"

echo "Hour | Valid Time   | GFS File"
echo "-----|--------------|--------------------------------------------------"

for fhr in $(seq 0 3 54); do
    # Calculate valid time from cycle
    VALID_TIME=$(date -d "${GFS_CYCLE_DATE} ${GFS_CYCLE}:00:00 + ${fhr} hours" +%Y%m%d%H 2>/dev/null || echo "N/A")
    FHR_STR=$(printf "%03d" $fhr)
    echo "f${FHR_STR} | ${VALID_TIME}   | gfs.t${GFS_CYCLE}z.pgrb2.0p25.f${FHR_STR}"
done

echo ""
echo "Total GFS files: 19 (f000 to f054 at 3-hourly intervals)"

# =============================================================================
# Expected HRRR file selection (based on Machuan's approach)
# =============================================================================
echo ""
echo "============================================"
echo "Expected HRRR Files (from Machuan's approach)"
echo "============================================"
echo ""

echo "=== Nowcast Period (hourly cycles with f01) ==="
echo ""
echo "Hour | Valid Time   | HRRR File"
echo "-----|--------------|--------------------------------------------------"

# Nowcast: 6 hours before run cycle
for back_hr in $(seq 6 -1 1); do
    PREV_HOUR=$((back_hr - 1))
    VALID_TIME=$(date -d "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00 - ${back_hr} hours" +%Y%m%d%H 2>/dev/null || echo "N/A")
    CYCLE_TIME=$(date -d "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00 - ${back_hr} hours - 1 hour" +%Y%m%d%H 2>/dev/null || echo "N/A")
    CYCLE_DATE=$(echo $CYCLE_TIME | cut -c1-8)
    CYCLE_HH=$(echo $CYCLE_TIME | cut -c9-10)
    echo "t-${back_hr}h | ${VALID_TIME}   | hrrr.${CYCLE_DATE}/hrrr.t${CYCLE_HH}z.wrfsfcf01.grib2"
done

echo ""
echo "=== Forecast Period (run cycle with extended forecasts) ==="
echo ""
echo "Hour | Valid Time   | HRRR File"
echo "-----|--------------|--------------------------------------------------"

# Forecast: 48 hours after run cycle
for fhr in $(seq 1 48); do
    VALID_TIME=$(date -d "${PDY:0:4}-${PDY:4:2}-${PDY:6:2} ${cyc}:00:00 + ${fhr} hours" +%Y%m%d%H 2>/dev/null || echo "N/A")
    FHR_STR=$(printf "%02d" $fhr)
    echo "f${FHR_STR}  | ${VALID_TIME}   | hrrr.${PDY}/hrrr.t${cyc}z.wrfsfcf${FHR_STR}.grib2"
done

echo ""
echo "Total HRRR files: 54 (6 nowcast + 48 forecast)"
echo ""

# =============================================================================
# Compare with what the rewritten script would select
# =============================================================================
echo "============================================"
echo "Logic Comparison with Rewritten Script"
echo "============================================"
echo ""
echo "GFS Logic in rewritten script:"
echo "  1. Calculate cycle 6h before valid time"
echo "  2. Round down to 00/06/12/18"
echo "  3. Try up to 4 cycles going back 24h"
echo "  4. Use forecast hour = valid_time - cycle_time"
echo ""
echo "For 00Z run with 18Z nowcast start:"
echo "  - Valid time 18Z -> Initial calc: 12Z -> Use 12Z or 18Z cycle"
echo "  - If 18Z previous day available -> f000"
echo "  - Script tries: 18Z, 12Z, 06Z, 00Z going backwards"
echo ""
echo "HRRR Logic in rewritten script:"
echo "  Nowcast (before run cycle):"
echo "    - Use previous hour's cycle with f01"
echo "    - Example: For 18Z valid, use 17Z cycle f01"
echo "  Forecast (after run cycle):"
echo "    - Use run cycle (00Z) with extended forecasts f01-f48"
echo ""
echo "============================================"
echo "Test Complete"
echo "============================================"
echo ""
echo "To test on WCOSS2:"
echo "  1. Copy nos_ofs_create_datm_forcing.sh to WCOSS2"
echo "  2. Set environment variables:"
echo "     export PDY=20241225"
echo "     export cyc=00"
echo "     export COMINgfs=/lfs/h1/ops/prod/com/gfs/v16.3"
echo "     export COMINhrrr=/lfs/h1/ops/prod/com/hrrr/v4.1"
echo "  3. Run: ./nos_ofs_create_datm_forcing.sh GFS25 ./output"
echo "  4. Check that 19 GFS files are extracted"
echo "  5. Run: ./nos_ofs_create_datm_forcing.sh HRRR ./output"
echo "  6. Check that 54 HRRR files are extracted"
echo ""
