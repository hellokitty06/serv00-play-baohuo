#!/bin/bash

# 颜色定义函数
colorize() {
    local color="$1"
    local text="$2"
    case "$color" in
        red)    echo -e "\033[0;31m$text\033[0m" ;;
        green)  echo -e "\033[0;32m$text\033[0m" ;;
        yellow) echo -e "\033[0;33m$text\033[0m" ;;
        blue)   echo -e "\033[0;34m$text\033[0m" ;;
        *)      echo "$text" ;;
    esac
}

# 从远程链接 获取配置文件内容
CONFIG_FILE="serv00.json"
if [ -f "$CONFIG_FILE" ]; then
    CONFIG_JSON=$(cat "$CONFIG_FILE")
else
    echo "配置文件 $CONFIG_FILE 不存在，脚本无法继续执行"
    exit 1
fi

# 从 JSON 中提取配置信息
NOTIFY_SERVICE=$(echo "$CONFIG_JSON" | jq -r '.NOTIFICATION')
BOT_TOKEN=$(echo "$CONFIG_JSON" | jq -r '.TELEGRAM_CONFIG.BOT_TOKEN')
CHAT_ID=$(echo "$CONFIG_JSON" | jq -r '.TELEGRAM_CONFIG.CHAT_ID')
WXPUSHER_TOKEN=$(echo "$CONFIG_JSON" | jq -r '.WXPUSHER_TOKEN')
PUSHPLUS_TOKEN=$(echo "$CONFIG_JSON" | jq -r '.PUSHPLUS_TOKEN')
WXPUSHER_USER_ID=$(echo "$CONFIG_JSON" | jq -r '.WXPUSHER_USER_ID')

SERVERS=$(echo "$CONFIG_JSON" | jq -r '.SERVERS | map(.SSH_USER + ":" +.SSH_PASS + ":" +.HOST) | join(",")')

SINGBOX=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.SINGBOX')
NEZHA_DASHBOARD=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.NEZHA_DASHBOARD')
NEZHA_AGENT=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.NEZHA_AGENT')
SUN_PANEL=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.SUN_PANEL')
WEB_SSH=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.WEB_SSH')
ALIST=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.ALIST')
ENABLE_ALL_SERVICES=$(echo "$CONFIG_JSON" | jq -r '.ENABLE_ALL_SERVICES')

# 启用所有服务时的配置
if [ "$ENABLE_ALL_SERVICES" == "true" ]; then
    SINGBOX=1
    NEZHA_DASHBOARD=1
    NEZHA_AGENT=1
    SUN_PANEL=1
    WEB_SSH=1
    ALIST=1
    colorize green "已启用所有服务"
fi

# 显示启用的通知服务和服务，添加分隔线
colorize blue "启用的通知服务："
case "$NOTIFY_SERVICE" in
    1) colorize green "Telegram" ;;
    2) colorize green "WxPusher" ;;
    3) colorize green "PushPlus" ;;
    4) colorize green "Telegram 和 WxPusher" ;;
    5) colorize green "Telegram 和 PushPlus" ;;
    *) colorize red "没有启用通知" ;;
esac
echo "——————————————————————————————"
colorize blue "启用的服务："
[[ "$SINGBOX" -eq 1 ]] && colorize green "Singbox"
[[ "$NEZHA_DASHBOARD" -eq 1 ]] && colorize green "Nezha Dashboard"
[[ "$NEZHA_AGENT" -eq 1 ]] && colorize green "Nezha Agent"
[[ "$SUN_PANEL" -eq 1 ]] && colorize green "Sun Panel"
[[ "$WEB_SSH" -eq 1 ]] && colorize green "Web SSH"
[[ "$ALIST" -eq 1 ]] && colorize green "Alist"
echo "———————————————————————————————"

# 发送 TELEGRAM 消息
send_tg_notification() {
  local title="$1"
  local content="$2"
  if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
    return
  fi
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{
      \"chat_id\": \"$CHAT_ID\",
      \"text\": \"$title $content\"
    }" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        colorize green "TG 消息发送成功"
    else
        colorize red "TG 消息发送失败"
    fi
}

# 发送 WXPUSHER 消息
send_wxpusher_message() {
  local title="$1"
  local content="$2"
  if [[ -z "$WXPUSHER_TOKEN" || -z "$WXPUSHER_USER_ID" ]]; then
    return
  fi
  curl -s -X POST "https://wxpusher.zjiecode.com/api/send/message" \
    -H "Content-Type: application/json" \
    -d "{
      \"appToken\": \"$WXPUSHER_TOKEN\",
      \"content\": \"$content\",
      \"title\": \"$title\",
      \"uids\": [\"$WXPUSHER_USER_ID\"]
    }" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        colorize green "WxPusher 消息发送成功"
    else
        colorize red "WxPusher 消息发送失败"
    fi
}

# 发送 PUSHPLUS 消息
send_pushplus_message() {
  local title="$1"
  local content="$2"
  if [[ -z "$PUSHPLUS_TOKEN" ]]; then
    return
  fi
  curl -s -X POST "http://www.pushplus.plus/send" \
    -H "Content-Type: application/json" \
    -d "{
      \"token\": \"$PUSHPLUS_TOKEN\",
      \"title\": \"$title\",
      \"content\": \"<pre>$content</pre>\"
    }"> /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        colorize green "PushPlus 消息发送成功"
    else
        colorize red "PushPlus 消息发送失败"
    fi
}

# 定义进程相关数组（对应不同服务进程及其友好名称）
declare -A processes=(
    ["singbox"]="Singbox"
    ["nezha-dashboard"]="Nezha Dashboard"
    ["nezha-agent"]="Nezha Agent"
    ["sun-panel"]="Sun Panel"
    ["wssh"]="Web SSH"
    ["alist"]="Alist"
)

# 新增函数用于检查进程状态
check_process_status() {
    local SSH_USER="$1"
    local SSH_PASS="$2"
    local SSH_HOST="$3"
    local process_list=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET -T "$SSH_USER@$SSH_HOST" "ps -A")
    local PROCESS_DETAILS=""
    for process in "${!processes[@]}"; do
        if echo "$process_list" | grep -q "$process"; then
            PROCESS_DETAILS+="    ${processes[$process]} |"
        fi
    done
    if [[ -n "$PROCESS_DETAILS" ]]; then
        echo "✅ 相关进程已启动：$PROCESS_DETAILS"
        return 0
    else
        echo "❌ 相关进程未启动"
        return 1
    fi
}

# 掩码处理函数：对用户名进行掩码，只显示最后三位
mask_username() {
    local username="$1"
    echo "****${username: -3}"
}

# 掩码处理函数：对服务器名进行掩码，只显示第一个字段（以.为分隔符）
mask_server() {
    local server="$1"
    echo "$server" | cut -d '.' -f 1
}

# 将逗号分隔的账户信息解析成一个数组
IFS=',' read -ra SERVER_LIST <<< "$SERVERS"  # 按逗号分隔服务器列表

# 用于汇总所有服务器执行情况的消息内容
combined_message=""  
index=1  # 索引
# 结果摘要标题
RESULT_SUMMARY="青龙自动进程内容：\n———————————————————————\n SERV00 \n———————————————————————\n"
# 发送合并后的结果摘要
combined_message="$RESULT_SUMMARY"
for SERVER in "${SERVER_LIST[@]}"; do
    # 分解每个服务器的用户名、密码、地址
    IFS=':' read -r SSH_USER SSH_PASS SSH_HOST <<< "$SERVER"
    # 获取掩码后的用户名和服务器名
    MASKED_USERNAME=$(mask_username "$SSH_USER")
    MASKED_SERVER=$(mask_server "$SSH_HOST")
    SERVER_ID="${MASKED_USERNAME}-${MASKED_SERVER}"

    colorize yellow "开始执行 ${SERVER_ID}"

    ssh_cmd=""
    services_started=""

    # 统一检查各个服务的目录是否存在，跳过不存在的目录
    check_and_add_service() {
        local service_name=$1
        local service_path=$2
        if sshpass -p "$SSH_PASS" ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" "test -d $service_path"; then
            ssh_cmd+="cd $service_path || true; pkill -f '$service_name' || true; nohup./$service_name > ${service_name}_$(date +%Y%m%d_%H%M%S).log 2>&1 & "
            services_started+="$service_name "  # 服务以空格分隔
        else
            colorize red "目录 $service_path 不存在，跳过 $service_name 服务"
        fi
    }

    # 依次检查每个服务的目录并启动
    [[ "$SINGBOX" -eq 1 ]] && check_and_add_service "singbox" "/home/$SSH_USER/serv00-play/singbox"
    [[ "$NEZHA_DASHBOARD" -eq 1 ]] && check_and_add_service "nezha-dashboard" "/home/$SSH_USER/nezha_app/dashboard"
    [[ "$NEZHA_AGENT" -eq 1 ]] && check_and_add_service "nezha-agent" "/home/$SSH_USER/nezha_app/agent"
    [[ "$SUN_PANEL" -eq 1 ]] && check_and_add_service "sun-panel" "/home/$SSH_USER/serv00-play/sunpanel"
    [[ "$WEB_SSH" -eq 1 ]] && check_and_add_service "wssh" "/home/$SSH_USER/serv00-play/webssh"
    [[ "$ALIST" -eq 1 ]] && check_and_add_service "alist" "/home/$SSH_USER/serv00-play/alist"


    # 执行构建的 SSH 命令
    sshpass -p "$SSH_PASS" ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" "$ssh_cmd"

    # 新增：检查进程状态
    if check_process_status "$SSH_USER" "$SSH_PASS" "$SSH_HOST"; then
        colorize green "相关进程在 $SSH_HOST 上已成功启动"
    else
        colorize red "部分或全部相关进程在 $SSH_HOST 上未启动，可能需要重启服务"
        # 这里可以根据具体需求添加进一步的重启逻辑，比如再次调用对应的启动服务函数等
    fi

    # 拼接服务启动后的状态，使用掩码后的用户名和服务器名
    if [ -n "$services_started" ]; then
        colorize green "✅ $index. $MASKED_USERNAME 【 $MASKED_SERVER 】登录成功 \n 拉起服务：$services_started\n———————————————————————"
        combined_message+="✅ $index. $MASKED_USERNAME 【 $MASKED_SERVER 】登录成功 \n 拉起服务：$services_started\n———————————————————————"
    else
        colorize red "❌ $index. $MASKED_USERNAME 【 $MASKED_SERVER 】登录失败"
        combined_message+="❌ $index. $MASKED_USERNAME 【 $MASKED_SERVER 】 - 登录失败\n"
    fi
    index=$((index + 1))
done

# 发送通知消息，消息内容中的用户名和服务器名也是掩码后的
if [ "$NOTIFY_SERVICE" -eq 1 ] || [ "$NOTIFY_SERVICE" -eq 4 ] || [ "$NOTIFY_SERVICE" -eq 5 ]; then
    send_tg_notification "$combined_message"
fi
if [ "$NOTIFY_SERVICE" -eq 2 ] || [ "$NOTIFY_SERVICE" -eq 4 ]; then
    send_wxpusher_message "VPS 自动进程内容" "$combined_message"
fi
if [ "$NOTIFY_SERVICE" -eq 3 ] || [ "$NOTIFY_SERVICE" -eq 5 ]; then
    send_pushplus_message "VPS 自动进程内容" "$combined_message"
fi

colorize green "脚本执行完毕，通知已发送！"
