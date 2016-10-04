#!/bin/bash

MONTH="01"

for i in {1..31}; do
  if [[ $i -lt 10 ]]; then
    DAY="0$i"
  else
    DAY="$i"
  fi

  echo "--> Starting Day $DAY"
  date
  hadoop jar /opt/cloudera/parcels/CDH/jars/hadoop-streaming-2.6.0-cdh5.7.0-SNAPSHOT.jar \
  -D mapred.reduce.tasks=0 -D mapred.map.tasks=600 -D mapred.output.compress=true \
  -D mapred.output.compression.codec=org.apache.hadoop.io.compress.GzipCodec \
  -D mapred.job.name="CEF->JSON [2016-$MONTH-$DAY]" -input /data/cef/2016${MONTH}${DAY}.cef.bz2 \
  -output /parsed/jsoncef/2016/${MONTH}/${DAY} -mapper "lognormalizer -r /tmp/cef.rf -e json -p </dev/stdin"
  date
done 
