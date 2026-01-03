#!/bin/bash
# command: nwm_collectfile.sh wcofs '202010190300' '202010230900'
# # module load prod_util/1.1.4
#
#
module load prod_util/2.0.14

COMINnwm='/lfs/h1/ops/prod/com/nwm/v3.0'

nwm_local='./nwm_harvest'

if [ ! -d $nwm_local ]; then
	mkdir -p $nwm_local
else
	rm $nwm_local/*
fi


#starttime='202508120000'
#endtime='202508140600'

FILE="nwm_source_sink_timestamp"
read -r starttime < "$FILE"
read -r endtime < <(tail -n +2 "$FILE")


dstr=${starttime:0:8}
hstr=${starttime:8:2}:${starttime:10:2}:00
starttime=$( date -d "${dstr} ${hstr} 0 hours ago" +%Y%m%d%H%M )

echo $starttime

if [ -f tmp_river.ctl ]; then
	  rm -f tmp_river.ctl
fi
touch tmp_river.ctl

domain1=""
domain="conus"


NWMfile=0
i=0

while [ "${thedate}" != "${endtime}" ]; do
  dstr=${starttime:0:8}
  hstr=${starttime:8:2}:${starttime:10:2}:00
  thedate=$( date -d "${dstr} ${hstr} ${i} hours" +%Y%m%d%H%M )

	echo "== thedate ==" $thedate

  YYNWM=${thedate:0:4}
  MMNWM=${thedate:4:2}
  DDNWM=${thedate:6:2}
  HHNWM=${thedate:8:2}
  nwm_dir=${COMINnwm}/nwm.${YYNWM}${MMNWM}${DDNWM}/analysis_assim${domain1}
  nwmfile=${nwm_dir}/nwm.t${HHNWM}z.analysis_assim.channel_rt.tm00.${domain}.nc

  if [ -f ${nwmfile} ]; then
    echo ${nwmfile} >> tmp_river.ctl
    NWMfile=$(( NWMfile + 1 ))
    fmtN=$(printf "%03d" "$NWMfile")
    cp ${nwmfile} ${nwm_local}/nwm_$fmtN.nc

   else
     break

  fi
  i=$(( i + 1 ))
done
                                      
#  End of searching Analysis NWM files

#  Search short-range NWM file
dstr=${thedate:0:8}
hstr=${thedate:8:2}:${thedate:10:2}:00


#i=0
#thedate=$( date -d "${dstr} ${hstr} ${i} hour ago" +%Y%m%d%H%M )

echo $thedate


YYNWM=${thedate:0:4}
MMNWM=${thedate:4:2}
DDNWM=${thedate:6:2}
HHNWM=${thedate:8:2}


YYNWM0=$YYNWM
MMNWM0=$MMNWM
DDNWM0=$DDNWM
HHNWM0=$HHNWM
thedate0=$thedate

echo "== hour ==" $HHNWM



nwm_dir=${COMINnwm}/nwm.${YYNWM}${MMNWM}${DDNWM}/short_range${domain1}
nwmfile=${nwm_dir}/nwm.t${HHNWM}z.short_range.channel_rt.f001.${domain}.nc

i=0

while [ ! -f ${nwmfile} ]; do
  i=$(( i + 1 ))
  thedate=$( date -d "${dstr} ${hstr} ${i} hour ago" +%Y%m%d%H%M )
  YYNWM=${thedate:0:4}
  MMNWM=${thedate:4:2}
  DDNWM=${thedate:6:2}
  HHNWM=${thedate:8:2}
  nwm_dir=${COMINnwm}/nwm.${YYNWM}${MMNWM}${DDNWM}/short_range${domain1}
  nwmfile=${nwm_dir}/nwm.t${HHNWM}z.short_range.channel_rt.f001.${domain}.nc

  if [ ${i} -gt 240 ]; then
    break
  fi
done

jj=0

dstr=${thedate0:0:8}
hstr=${thedate0:8:2}:${thedate0:10:2}:00


for j in $(seq -f "%03g" $i 45); do

  nwmfile=${nwm_dir}/nwm.t${HHNWM}z.short_range.channel_rt.f${j}.${domain}.nc
  if [ -f ${nwmfile} ]; then
	          let jj++

	    thedate=$( date -d "${dstr} ${hstr} ${jj} hour" +%Y%m%d%H%M )

	 echo $thedate

    echo ${nwmfile} >> tmp_river.ctl
    NWMfile=$(( NWMfile + 1 ))
  
    fmtN=$(printf "%03d" "$NWMfile")
    cp ${nwmfile} ${nwm_local}/nwm_$fmtN.nc


  fi
done
#  End of searching short-range NWM files

thedate0=$thedate

YYNWM0=${thedate:0:4}
MMNWM0=${thedate:4:2}
DDNWM0=${thedate:6:2}
HHNWM0=${thedate:8:2}


#################


echo "=== mmgp NWMfile =="  $NWMfile

nleft=$((72- $NWMfile))


lastd=${endtime:0:8}
stard=${starttime:0:8}
thedate=${endtime:0:8}
day5ago=$( date -d "${stard:0:8} -3 day" +%Y%m%d )

echo "=== mmgp day5ago ==" $day5ago


DATE0="$YYNWM0-$MMNWM0-$DDNWM0"
SECONDS0=$(date -d "$DATE0" +%s)


icheck=0
while [ "${thedate}" != "${day5ago}" ]; do


  YYNWM=${thedate:0:4}
  MMNWM=${thedate:4:2}
  DDNWM=${thedate:6:2}
  HHNWM=${thedate:8:2}

DATE="$YYNWM-$MMNWM-$DDNWM"
SECONDS=$(date -d "$DATE" +%s)




  nwm_dir=${COMINnwm}/nwm.${YYNWM}${MMNWM}${DDNWM}/medium_range${domain1}_mem1
  for j in 18 12 06 00; do
    nwmfile=${nwm_dir}/nwm.t${j}z.medium_range.channel_rt_1.f003.${domain}.nc
    if [ -f ${nwmfile} ]; then
	ddif=$(($SECONDS0 - $SECONDS))
	difh=$((ddif / 3600))

	jstart=$(($difh + 10#${HHNWM0} - 10#$j))
	nend=$(($jstart+$nleft))
      for i in $(seq -f "%03g" $jstart $nend); do
        nwmfile=${nwm_dir}/nwm.t${j}z.medium_range.channel_rt_1.f${i}.${domain}.nc
        if [ -f ${nwmfile} ]; then
          echo ${nwmfile} >> tmp_river.ctl
          NWMfile=$(( NWMfile + 1 ))
	    fmtN=$(printf "%03d" "$NWMfile")
		cp ${nwmfile} ${nwm_local}/nwm_$fmtN.nc



        fi
      done
      icheck=1
      break
    fi
  done

  if [ ${icheck} -eq 1 ]; then
    break
  else
    thedate=$( date -d "${thedate:0:8} -1 day" +%Y%m%d )

  fi

done




