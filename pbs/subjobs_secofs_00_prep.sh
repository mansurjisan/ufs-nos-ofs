#!/bin/bash
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

rm -f /lfs/h1/nos/ptmp/mansur.jisan/rpt/v3.7.0/secofs_*_00.out
rm -f /lfs/h1/nos/ptmp/mansur.jisan/rpt/v3.7.0/secofs_*_00.err

export LSFDIR=/lfs/h1/nos/estofs/noscrub/mansur.jisan/packages/nosofs.v3.7.0/pbs 

# Submit ONLY the PREP job
PREP=$(qsub $LSFDIR/jnos_secofs_prep_00.pbs) 
echo "Submitted PREP job: $PREP"
echo "Monitor with: qstat -u $USER"
echo "Check logs at: /lfs/h1/nos/ptmp/mansur.jisan/rpt/v3.7.0/"

# COMMENTED OUT - Not running NOWCAST_FCST and AWS
# NFRUN=$(qsub -W depend=afterok:$PREP $LSFDIR/jnos_secofs_nowcst_fcst_00.pbs)
# qsub -W depend=afterok:$NFRUN $LSFDIR/jnos_secofs_aws_00.pbs
