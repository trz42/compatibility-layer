#!/bin/bash

data=${1}
datafile=${data//@/}
echo "datafile >${datafile}<"

smee=${SMEE}
secret=${KEY}

curl=$(which curl)

headersfile=$(mktemp)
echo "writing headers to ${headersfile}"

function add_header() {
  echo "${1}" >> ${headersfile}
}

#add_header "'Accept: */*'"
add_header "Content-Type: application/json"
#add_header "'User-Agent: TRZ-HEARTBEAT/v001'"
event_id=$(uuidgen | tr "[:upper:]" "[:lower:]")
add_header "X-GitHub-Delivery: ${event_id}"
add_header "X-GitHub-Event: bot_heartbeat"
add_header "X-GitHub-Hook-ID: 397476584"
add_header "X-GitHub-Hook-Installation-Target-ID: 283684"
add_header "X-GitHub-Hook-Installation-Target-Type: integration"
sha1sum=$(shasum --algorithm 1 ${datafile} | cut -d ' ' -f 1)
sha256sum=$(shasum --algorithm 256 ${datafile} | cut -d ' ' -f 1)
add_header "X-Hub-Signature: sha1=${sha1sum}"
add_header "X-Hub-Signature-256: sha256=${sha256sum}"

echo "headers: >$(cat ${headersfile})<"

echo "POSTing data '${data}' to smee ${smee}"
echo ${curl} --request POST --user-agent trz/1 --header @${headersfile} --data ${data} ${smee}
${curl} --request POST --user-agent trz/1 --header @${headersfile} --data ${data} ${smee}
