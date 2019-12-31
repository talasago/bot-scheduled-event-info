#!/bin/bash

set -eu

# 定数
readonly CURRENT_DATE=$(date +%Y%m%d)
readonly WORKDIR=/$HOME/bot-scheduled-event-info
readonly LOGFILE=${WORKDIR}/log/event_notice_send${CURRENT_DATE}.log

# ログ用
exec 2> ${LOGFILE}

# tempファイル
tmp_ec2_tags=$(mktemp /tmp/tmp_ec2_tags-XXXXXX)
tmp_api_res=$(mktemp /tmp/tmp_api_res-XXXXXX)
trap 'rm -rf /tmp/tmp_*' EXIT

# EC2のタグを取得
readonly EC2_INSTANCE_NAME="bot-scheduled-event-info"
readonly RESOURCE_ID=$(aws ec2 describe-tags --filters Name=value,Values=${EC2_INSTANCE_NAME} --output text | awk '{print $3}')
readonly EC2_TAGS=$(aws ec2 describe-tags --filters Name=resource-id,Values=${RESOURCE_ID} --output text)
readonly WEBHOOK_URL=$(echo "${EC2_TAGS}" | awk '$2=="WEBHOOK_URL"{print $5}')
readonly CONNPASS_API_NICKNAME=$(echo "${EC2_TAGS}" | awk '$2=="CONNPASS_API_NICKNAME"{print $5}')
readonly SEND_CHANNEL=$(echo "${EC2_TAGS}" | awk '$2=="SEND_CHANNEL"{print $5}')

# EC2のタグを元にconnpassのAPIにアクセス
curl -sX GET https://connpass.com/api/v1/event/?nickname=${CONNPASS_API_NICKNAME}\&ymd=${CURRENT_DATE} | jq . > ${tmp_api_res}

echo ========connpassAPIレスポンス============== >> ${LOGFILE}
cat ${tmp_api_res}                             >> ${LOGFILE}
echo -e "\n\n\n"                                   >> ${LOGFILE}

readonly results_returned=$(cat ${tmp_api_res} | jq .results_returned)

# 取得したイベントの件数の分だけslackに通知を送信
for ((i=0;i<results_returned;i++)); do
  title=$(jq -r .events[${i}].title ${tmp_api_res})
  event_url=$(jq -r .events[${i}].event_url ${tmp_api_res})
  started_at=$(jq -r .events[${i}].started_at ${tmp_api_res} | awk '{print substr($1,12,5)}')
  ended_at=$(jq -r .events[${i}].ended_at ${tmp_api_res} | awk '{print substr($1,12,5)}')
  place=$(jq -r .events[${i}].place ${tmp_api_res})
  address=$(jq -r .events[${i}].address ${tmp_api_res})

  data=$(cat << EOF
    payload={
      "channel": "${SEND_CHANNEL}",
      "username": "【リマインダー】本日参加予定の勉強会",
      "icon_emoji": ":pencil2:",
      "attachments": [{
        "pretext": "<!channel> ${started_at}〜${ended_at}",
        "title": "${title}",
        "text": "${address} ${place}\n ${event_url}"
      }]
    }
EOF
)

  echo ===============slack送信================== >> ${LOGFILE}
  echo "${data}" >> ${LOGFILE}
  curl -sX POST --data-urlencode "${data}" ${WEBHOOK_URL} >> ${LOGFILE}
  echo -e "\n\n\n" >> ${LOGFILE}
done
