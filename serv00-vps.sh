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
# 自动获取脚本的路径
SCRIPT_PATH=$(realpath "$0")

# 设置每隔 8 小时执行一次
CRON_JOB="0 */8 * * * $SCRIPT_PATH"  # 使用自动获取的脚本路径

# 检查是否已存在该 cron 任务
if crontab -l | grep -F "$CRON_JOB" > /dev/null; then
    echo -e "${GREEN}定时任务已存在，跳过添加${NC}"
else
    (crontab -l; echo "$CRON_JOB") | crontab - 
    echo -e "${YELLOW}已添加定时任务，每8小时执行一次${NC}"
fi

# 显示当前的 cron 配置，仅显示当前脚本的定时任务
echo -e "${YELLOW}当前的 cron 配置如下：${NC}"
crontab -l | grep "$SCRIPT_PATH"

# 安装依赖包
install_packages() {
    if [ -f /etc/debian_version ]; then
        package_manager="apt-get install -y"
        packages="sshpass curl netcat-openbsd cron jq"
    elif [ -f /etc/redhat-release ]; then
        package_manager="yum install -y"
        packages="sshpass curl netcat-openbsd cron jq"
    elif [ -f /etc/fedora-release ]; then
        package_manager="dnf install -y"
        packages="sshpass curl netcat-openbsd cron jq"
    elif [ -f /etc/alpine-release ]; then
        package_manager="apk add --no-cache"
        packages="openssh-client curl netcat-openbsd cronie jq"
    else
        echo -e "${RED}不支持的系统架构！${NC}"
        exit 1
    fi
    $package_manager $packages > /dev/null
}

install_packages


# 从远程 URL 获取配置文件内容
CONFIG_URL="https://XXXXXXX/serv00.json"
CONFIG_JSON=$(curl -s "$CONFIG_URL")

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

# 显示启用的通知服务和服务
colorize blue "启用的通知服务："
case "$NOTIFY_SERVICE" in
    1) colorize green "Telegram" ;;
    2) colorize green "WxPusher" ;;
    3) colorize green "PushPlus" ;;
    4) colorize green "Telegram 和 WxPusher" ;;
    5) colorize green "Telegram 和 PushPlus" ;;
    *) colorize red "没有启用通知" ;;
esac

colorize blue "启用的服务："
[[ "$SINGBOX" -eq 1 ]] && colorize green "Singbox"
[[ "$NEZHA_DASHBOARD" -eq 1 ]] && colorize green "Nezha Dashboard"
[[ "$NEZHA_AGENT" -eq 1 ]] && colorize green "Nezha Agent"
[[ "$SUN_PANEL" -eq 1 ]] && colorize green "Sun Panel"
[[ "$WEB_SSH" -eq 1 ]] && colorize green "Web SSH"
[[ "$ALIST" -eq 1 ]] && colorize green "Alist"

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

# WxPusher 发送消息函数
send_wxpusher_message() {
    local title="$1"
    local content="$2"
    curl -s -X POST "https://wxpusher.zjiecode.com/api/send/message" \
        -H "Content-Type: application/json" \
        -d "{
            \"appToken\": \"$WXPUSHER_TOKEN\",
            \"content\": \"$escaped_content\",
            \"title\": \"$title\",
            \"uids\": [\"$WXPUSHER_USER_ID\"]
        }" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        colorize green "WxPusher 消息发送成功"
    else
        colorize red "WxPusher 消息发送失败"
    fi
}

# 发送 PushPlus 消息的函数
send_pushplus_message() {
    local title="$1"
    curl -s -X POST "http://www.pushplus.plus/send" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$PUSHPLUS_TOKEN\",\"title\":\"$title\",\"content\":\"<pre>$escaped_content</pre>\"}" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        colorize green "PushPlus 消息发送成功"
    else
        colorize red "PushPlus 消息发送失败"
    fi
}

# 将逗号分隔的账户信息解析成一个数组
IFS=',' read -ra SERVER_LIST <<< "$SERVERS"  # 按逗号分隔服务器列表
combined_message=""  # 用于汇总所有服务器执行情况的消息内容
index=1  # 索引
# 结果摘要标题
RESULT_SUMMARY="青龙自动进程内容：\n———————————————————————\n SERV00 \n———————————————————————\n"
# 发送合并后的结果摘要
combined_message="$RESULT_SUMMARY"
for SERVER in "${SERVER_LIST[@]}"; do
    # 分解每个服务器的用户名、密码、地址
    IFS=':' read -r SSH_USER SSH_PASS SSH_HOST <<< "$SERVER"
    SERVER_ID="${SSH_USER}-${SSH_HOST}"

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

    # 拼接服务启动后的状态
    if [ -n "$services_started" ]; then
        colorize green "✅ $index. $SSH_USER 【 $SSH_HOST 】登录成功，启动服务：$services_started"
        combined_message+="✅ $index. $SSH_USER 【 $SSH_HOST 】登录成功 \n 拉起服务：$services_started\n"
    else
        colorize red "❌ $index. $SSH_USER 【 $SSH_HOST 】登录失败"
        combined_message+="❌ $index. $SSH_USER 【 $SSH_HOST 】 - 登录失败\n"
    fi
    index=$((index + 1))
done

# 发送通知消息
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
