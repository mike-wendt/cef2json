# cef2json

## Overview
One method for dealing with CEF security event files by converting them from CEF to JSON using a modified version of [liblognorm](https://github.com/mike-wendt/liblognorm/tree/cef-master). This version has been changed to handle the CEF log data that was received from ArcSight loggers. **NOTE:** This has only been tested on Ubuntu systems but should work on others.

## Installation for Ubuntu
Build the modified version of [liblognorm](https://github.com/mike-wendt/liblognorm/tree/cef-master) on the node(s) used to process the CEF data.

1. Checkout the `cef-master` branch for building

  ```
  git clone https://github.com/mike-wendt/liblognorm.git
  cd liblognorm
  git checkout cef-master
  ```

2. Install Pre-reqs

  ```
  sudo apt-get install -y make libtool pkg-config autoconf automake
  ```

3. Build/Install

  ```
  autoreconf -vfi
  ./configure
  make
  sudo make install
  ```

4. Post-install to load libraries
  
  ```
  sudo ldconfig
  ```

## Usage
For CEF parsing we need a rule file to work with `liblognorm`

1. Create a file at `~/cef.rf`

  ```
  rule=:%cef:cef%
  ```
2. Run `lognormalizer` with input data with output data sent to STDOUT

  ```
  lognormalizer -r ~/cef.rf -e json -p < ~/input.cef
  ```

3. Redirect data to a file for easier processing

  ```
  lognormalizer -r ~/cef.rf -e json -p < ~/input.cef > output.json
  ```

4. Output data will be one JSON object per line for each CEF record

## MapReduce for Scale
For larger datasets streaming MapReduce can be used to parallelize the task across many nodes reducing the time necessary to convert all of the CEF data. **NOTE:** This requires a Hadoop cluster with HDFS and YARN/MapReduce.

### Pre-reqs

1. Install `liblognorm` as above to all worker nodes
2. Install rule file in a common place on all workers with read access by MapReduce like `/tmp/cef.rf`
3. Load all CEF data into HDFS

### Running Conversion Task
The streaming MapReduce can be started with a single command and the BASH variables `${MONTH},${DAY}`:
```
hadoop jar /opt/cloudera/parcels/CDH/jars/hadoop-streaming-2.6.0-cdh5.7.0-SNAPSHOT.jar \
-D mapred.reduce.tasks=0 -D mapred.map.tasks=600 -D mapred.output.compress=true \
-D mapred.output.compression.codec=org.apache.hadoop.io.compress.GzipCodec \
-D mapred.job.name="CEF->JSON [2016-$MONTH-$DAY]" -input /data/cef/2016${MONTH}${DAY}.cef.bz2 \
-output /parsed/jsoncef/2016/${MONTH}/${DAY} -mapper "lognormalizer -r /tmp/cef.rf -e json -p </dev/stdin"
```

This command will run the log normalizer on a single day across the cluster, compressing the JSON output with GZip encoding to save space. Notice the number of reduce tasks are explicitly set to zero as we do not have a need to reduce the data.

#### Running Conversion for an Entire Month
If you want to process an entire month the above command can be made into a BASH script to process each day after the previous day has finished:
```
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
```

### Accessing Results
Results will be stored in the output path but in files named `part-00000` with increasing numbers. Use a wildcard as in the next section to load and process all of the output records at once.

Good practice here would be to convert all CEF data for a single month, or week at one time. Alternatively you can convert by day just be mindful of the output/save path so processing of the files can be done easily. For example a good path would be `/parsed/jsoncef/2016/06/30/part*` allows for loading of 1 day up to many days/months with wildcards like `/parsed/jsoncef/2016/06/*/part*` which loads the entire month of June 2016.

## Working with Data in pySpark
Once the data has been converted into JSON format, Spark can natively load and parse the JSON data collapsing the many keys from the vary messages into a single data frame. Some example code to load the data from HDFS is below:

1. Load parsed data from HDFS into Spark

  ```
  from pyspark.sql import SQLContext
  sqlContext = SQLContext(sc)
  json = sqlContext.read.json("hdfs://hdfshostname:8020/parsed/jsoncef/2016/06/30/part*")
  ```

2. Print schema to load all available attributes from CEF fields
  
  ```
  json.printSchema()
  ```
  * Which should print something similar to:
  ```
  root
  |-- cef: struct (nullable = true)
  |    |-- DeviceProduct: string (nullable = true)
  |    |-- DeviceVendor: string (nullable = true)
  |    |-- DeviceVersion: string (nullable = true)
  |    |-- Extensions: struct (nullable = true)
  |    |    |-- _cefVer: string (nullable = true)
            <LIST OF ALL PARSED FIELDS FROM CEF>
  |    |-- Name: string (nullable = true)
  |    |-- Severity: string (nullable = true)
  |    |-- SignatureID: string (nullable = true)
  ```
3. Register the `json` data frame as a temporary table to allow SQL searches and exploration

  ```
  json.registerTempTable("json")
  msg = sqlContext.sql("SELECT * from json where cef.Name like '%Malware%'")
  msg.count()
  ```

4. Use `take()` to get a subset of the matching records

  ```
  msg.take(20)
  ```
  * Returns the first 20 matching records
    
## License
Released under MIT License to help others who are trying to parse this challenging data format.
