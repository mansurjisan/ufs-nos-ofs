#!/bin/bash
. /lfs/h1/nos/nosofs/noscrub/machuan.peng/packages/nosofs.v3.7.0/versions/run.ver
module load envvar/${envvars_ver:?}
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load craype/${craype_ver}
module load intel/${intel_ver}
if [ ! -d /lfs/h1/nos/ptmp/machuan.peng/execlog/v3.7.0 ]; then 
   mkdir -p /lfs/h1/nos/ptmp/machuan.peng/execlog/v3.7.0 
fi 
if [ ! -d /lfs/h1/nos/ptmp/machuan.peng/rpt/v3.7.0 ]; then 
   mkdir -p /lfs/h1/nos/ptmp/machuan.peng/rpt/v3.7.0 
fi 
rm -f /lfs/h1/nos/ptmp/machuan.peng/rpt/v3.7.0/dbofs_*_06.out
rm -f /lfs/h1/nos/ptmp/machuan.peng/rpt/v3.7.0/dbofs_*_06.err
export LSFDIR=/lfs/h1/nos/nosofs/noscrub/machuan.peng/packages/nosofs.v3.7.0/pbs 
PREP=$(qsub  $LSFDIR/jnos_dbofs_prep_06.pbs) 
NFRUN=$(qsub -W depend=afterok:$PREP $LSFDIR/jnos_dbofs_nowcst_fcst_06.pbs)
qsub -W depend=afterok:$NFRUN $LSFDIR/jnos_dbofs_aws_06.pbs
