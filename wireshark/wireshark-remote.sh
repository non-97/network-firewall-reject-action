#!/bin/bash
# Name
#   wireshark-remote
#
# format
#   wireshark-remote.sh [-c config_path]
#
# description
#   ssh経由でtcpdumpを実行した結果をwiresharkに転送することによって
#   間接的にwiresharkによるリモートキャプチャーする
#
# requirements
#   1. !requiretty設定
#     リモートホスト(EC2)でtcpdumpを実行するユーザ(ec2-user)に
#     コマンド(tcpdump)を実行するときにTTYを要求しない設定を追加する
#     例.ec2-userの場合、visudoにて以下の行を追加
#       Defaults:ec2-user !requiretty
#
#   2. Wiresharのキャプチャー開始
#     このシェルスクリプトを実行して起動したWiresharkのインターフェイスで - を選択する
#
# return
#      0 =  SUCCESS
#      0 != FAILED
#

set -euo pipefail

# kill child process
trap 'pkill -P $$' HUP
trap 'pkill -P $$' INT
trap 'pkill -P $$' TERM

##############################################################################
# Main
#

function main () {
  declare -r snaplen=262144
  declare -r keep_alive=60

  local portforward_option
  local config
  local result

  # include config. (default: wireshark-remote.conf)
  if [[ "$#" == 2 && "$1" == "-c" ]]; then
    config="$2"
  else
    config="./wireshark/wireshark-remote.conf"
  fi

  # load config
  if [[ ! -f "${config}" ]]; then
    echo "Invalid config file : ${config}"
    exit 1
  fi
  source "${config}"

  # Portforwarding as child process.
  if [[ -n "${portforward_port}" ]]; then

    aws ssm start-session --target "${portforward_instance_id}" \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["22"],"localPortNumber":["'"${portforward_port}"'"]}' &

    portforward_option="-p ${portforward_port}"
  fi

  sleep 5

  # set Filter
  if [[ -n "${filter}" ]]; then
    filter="and \(${filter}\)"
  fi

  # remote command
  ssh \
    -i "${key_pair}" \
    -C \
    -o ServerAliveInterval="${keep_alive}" \
    -o StrictHostKeyChecking=no \
    "${ssh_user_name}@${connect_hostname}" \
    "${portforward_option}" \
    sudo tcpdump \
      -U \
      -i "${interface}" \
      -s "${snaplen}" \
      -w - \
      "not \(host ${target_private_ipaddr} and tcp port 22\) ${filter}" \
    | wireshark -i -
  
  result=$?
  if (( ${result} == 0 )); then
    pkill -P $$
  fi

  exit ${result}
}

main "$@"