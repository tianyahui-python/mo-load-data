#!/usr/bin/env bash

pip3 install shyaml

if [[ $# -eq 0 ]];then
    echo "No parameters provided,please use -H to get help. "
fi

TIMES=1
STATUS=0

WORKSPACE=$(cd `dirname $0`; pwd)
SERVER="127.0.0.1"
PORT=6001
USER=dump
PASS=111
while getopts ":h:P:u:p:c:H" opt
do
    case $opt in
        h)
        SERVER="${OPTARG}"
        ;;
        P)
        PORT=${OPTARG}
        ;;
        u)
        USER="${OPTARG}"
        ;;
        p)
        PASS="${OPTARG}"
        ;;
        c)
        CONFIG="${OPTARG}"
        ;;
        H)
        echo -e "Usage:　bash load.sh [option] [param] ...\nExcute mo load data task"
        echo -e "   -h  mo server address"
        echo -e "   -P  mo server port"
        echo -e "   -u  mo server username"
        echo -e "   -p  mo server password of the user[-u]"
        echo -e "   -c  designate the case config file that the load.sh will run, if None, will run all config in the dir ./cases/"
        echo -e "Examples:"
        echo "   bash load.sh"
	      echo -e "   bash run.sh -c cases/xxx.yml "
        echo -e "   bash run.sh -h 127.0.0.1 -udump -p111 -P6001 -c cases/xxx.yml"
	echo "For more support,please email to sudong@matrixorigin.io"
        exit 1
        ;;
        ?)
        echo "Unkown parameter,please use -H to get help."
        exit 1;;
    esac
done

function load() {
    local db=`cat ${CONFIG} | shyaml get-value db`
    local table=`cat ${CONFIG} | shyaml get-value table`
    local count=`cat ${CONFIG} | shyaml get-value count`
    local file=`cat ${CONFIG} | shyaml get-value path`
    local ddl=`cat ${CONFIG} | shyaml get-value ddl`
    local terminated=`cat ${CONFIG} | shyaml get-value terminated`
    local s3=`cat ${CONFIG} | shyaml get-value s3`
    if [ "${s3}" != "true" ]; then
      file=${WORKSPACE}/data/${file}
      echo $file
    fi
    
    local sql="load data infile '${file}' into table ${db}.${table} FIELDS TERMINATED BY '${terminated}' LINES TERMINATED BY '\n';"
    echo -e "Start to load data from file ${file} into table ${db}.${table},please wait....." | tee -a ${WORKSPACE}/run.log
    echo "${sql}"
    startTime=`date +%s.%N`
    result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} -e "${sql}" 2>&1`
    if [ $? -eq 0 ];then
      endTime=`date +%s.%N`
      getTiming $startTime $endTime
      echo -e "The data for table ${db}.${table} has been loaded successfully,,and cost: ${cost}" | tee -a ${WORKSPACE}/run.log
      local name=`basename ${CONFIG} .sql`
      echo "${name}:${cost}" >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
      check
      if [ $? -eq 1 ];then
        STATUS=1
      fi
    else
      STATUS=1
      echo -e "The data for table ${db}.${table} has failed to be loaded." | tee -a ${WORKSPACE}/run.log
      echo "${result}"
      local name=`basename ${CONFIG} .sql`
      echo "${name}: ${result}" | awk 'NR>1' | tee -a >> ${WORKSPACE}/report/cost.txt | tee -a ${WORKSPACE}/run.log
    fi
}

function getTiming(){
    start=$1
    end=$2

    start_s=`echo $start | cut -d '.' -f 1`
    start_ns=`echo $start | cut -d '.' -f 2`
    end_s=`echo $end | cut -d '.' -f 1`
    end_ns=`echo $end | cut -d '.' -f 2`

    time_micro=$(( (10#$end_s-10#$start_s)*1000000 + (10#$end_ns/1000 - 10#$start_ns/1000) ))
    time_ms=`expr $time_micro/1000  | bc `

    cost=${time_ms}
}

function check() {
    local db=`cat ${CONFIG} | shyaml get-value db`
    local table=`cat ${CONFIG} | shyaml get-value table`
    local count=`cat ${CONFIG} | shyaml get-value count`
    local sql="select count(*) from ${db}.${table};"
    local result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} {db} -e "${sql}" 2>&1`
    local rcount=`echo "${result}" | awk 'NR>2'`
    if [ "${rcount}" != "${count}" ]; then
      STATUS=1
      echo -e "The table[${db}.${table}] size is not correct, expect:${count}, but real[${rcount}]" | tee -a ${WORKSPACE}/run.log
      return 1
    fi
    return 0
}

function createSchema() {
    local db=`cat ${CONFIG} | shyaml get-value db`
    local table=`cat ${CONFIG} | shyaml get-value table`
    local count=`cat ${CONFIG} | shyaml get-value count`
    local ddl=`cat ${CONFIG} | shyaml get-value ddl`
    
    local cdb="create database if not exists ${db};"
    local result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} -e "${cdb}" 2>&1`
    if [ $? -ne 0 ];then
      echo -e "The database ${db} cant not be created. Error: ${result}"  | tee -a ${WORKSPACE}/run.log
      return 1
    fi

    result=`mysql -h${SERVER} -P${PORT} -u${USER} -p${PASS} -e "use ${db};${ddl}" 2>&1`
    if [ $? -ne 0 ];then
      echo -e "The table ${db}.${table} cant not be created. Error: ${result}"  | tee -a ${WORKSPACE}/run.log
      return 1
    fi
    
    return 0;
    
}


createSchema
load

if [ $STATUS -eq 1 ];then
   echo "This test has been failed, more info, please see the log" | tee -a ${WORKSPACE}/run.log
   exit 1
fi

