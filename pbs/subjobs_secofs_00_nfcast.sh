#!/bin/bash
# subjobs_secofs_00_forecast_only.sh

. /lfs/h1/nos/estofs/noscrub/mansur.jisan/packages/nosofs.v3.7.0/versions/run.ver
module load envvar/${envvars_ver:?}
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load craype/${craype_ver}
module load intel/${intel_ver}

if [ ! -d /lfs/h1/nos/ptmp/mansur.jisan/execlog/v3.7.0 ]; then
   mkdir -p /lfs/h1/nos/ptmp/mansur.jisan/execlog/v3.7.0
fi

if [ ! -d /lfs/h1/nos/ptmp/mansur.jisan/rpt/v3.7.0 ]; then
   mkdir -p /lfs/h1/nos/ptmp/mansur.jisan/rpt/v3.7.0
fi

# Clean up old forecast logs
rm -f /lfs/h1/nos/ptmp/mansur.jisan/rpt/v3.7.0/secofs_nowcst_fcst_00.out
rm -f /lfs/h1/nos/ptmp/mansur.jisan/rpt/v3.7.0/secofs_nowcst_fcst_00.err

export LSFDIR=/lfs/h1/nos/estofs/noscrub/mansur.jisan/packages/nosofs.v3.7.0/pbs

# SKIP PREP - Already completed
echo "Skipping PREP stage - using existing forcing files"
echo "Forcing files from: /lfs/h1/nos/ptmp/mansur.jisan/com/nosofs/v3.7/secofs.20251009"

# Submit ONLY the nowcast/forecast job
NFRUN=$(qsub $LSFDIR/jnos_secofs_nowcst_fcst_00.pbs)
echo "Submitted NOWCAST_FCST job: $NFRUN"
echo "Monitor with: qstat -u $USER"
echo "Check logs at: /lfs/h1/nos/ptmp/mansur.jisan/rpt/v3.7.0/secofs_nowcst_fcst_00.out"

# SKIP AWS - Comment out if you don't need post-processing
# qsub -W depend=afterok:$NFRUN $LSFDIR/jnos_secofs_aws_00.pbs
