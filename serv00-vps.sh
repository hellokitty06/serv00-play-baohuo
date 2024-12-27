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
CONFIG_URL="https://api.zjcc.cloudns.be/CSV/main/serv00.json"
CONFIG_JSON=$(curl -s "$CONFIG_URL")

# 从 JSON 格式的配置文件中提取通知服务相关的配置信息
# 例如通知服务的类型（Telegram、WxPusher、PushPlus等）以及对应服务所需的各种token、id等
NOTIFY_SERVICE=$(echo "$CONFIG_JSON" | jq -r '.NOTIFICATION')
BOT_TOKEN=$(echo "$CONFIG_JSON" | jq -r '.TELEGRAM_CONFIG.BOT_TOKEN')
CHAT_ID=$(echo "$CONFIG_JSON" | jq -r '.TELEGRAM_CONFIG.CHAT_ID')
WXPUSHER_TOKEN=$(echo "$CONFIG_JSON" | jq -r '.WXPUSHER_TOKEN')
PUSHPLUS_TOKEN=$(echo "$CONFIG_JSON" | jq -r '.PUSHPLUS_TOKEN')
WXPUSHER_USER_ID=$(echo "$CONFIG_JSON" | jq -r '.WXPUSHER_USER_ID')

# 提取服务器相关信息，将多个服务器的信息以逗号分隔的字符串形式存储
# 每个服务器信息包含用户名、密码和主机地址，后续会据此进行服务器相关操作
SERVERS=$(echo "$CONFIG_JSON" | jq -r '.SERVERS | map(.SSH_USER + ":" +.SSH_PASS + ":" +.HOST) | join(",")')

# 提取各个服务（如Singbox、Nezha Dashboard等）的启用状态配置信息
# 用于判断是否需要启动相应服务
SINGBOX=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.SINGBOX')
NEZHA_DASHBOARD=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.NEZHA_DASHBOARD')
NEZHA_AGENT=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.NEZHA_AGENT')
SUN_PANEL=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.SUN_PANEL')
WEB_SSH=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.WEB_SSH')
ALIST=$(echo "$CONFIG_JSON" | jq -r '.FEATURES.ALIST')
ENABLE_ALL_SERVICES=$(echo "$CONFIG_JSON" | jq -r '.ENABLE_ALL_SERVICES')

# 启用所有服务时的配置，若配置中启用所有服务的标识为true
# 则将各个服务的启用状态都设置为1，表示全部启用，并输出提示信息
if [ "$ENABLE_ALL_SERVICES" == "true" ]; then
    SINGBOX=1
    NEZHA_DASHBOARD=1
    NEZHA_AGENT=1
    SUN_PANEL=1
    WEB_SSH=1
    ALIST=1
    colorize green "已启用所有服务"
fi

# 显示启用的通知服务，根据不同的配置值展示相应的通知服务名称
# 并添加分隔线用于区分不同部分的显示内容
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

# 显示启用的服务，根据各个服务的启用状态配置，展示相应启用的服务名称
# 同样添加分隔线用于区分不同部分的显示内容
colorize blue "启用的服务："
[[ "$SINGBOX" -eq 1 ]] && colorize green "Singbox"
[[ "$NEZHA_DASHBOARD" -eq 1 ]] && colorize green "Nezha Dashboard"
[[ "$NEZHA_AGENT" -eq 1 ]] && colorize green "Nezha Agent"
[[ "$SUN_PANEL" -eq 1 ]] && colorize green "Sun Panel"
[[ "$WEB_SSH" -eq 1 ]] && colorize green "Web SSH"
[[ "$ALIST" -eq 1 ]] && colorize green "Alist"
echo "———————————————————————————————"

# 发送 TELEGRAM 消息的函数
# 接收消息标题和内容作为参数，在具备BOT_TOKEN和CHAT_ID的情况下
# 通过curl命令向Telegram API发送消息，并根据发送结果输出相应提示信息
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

# 发送 WXPUSHER 消息的函数
# 接收消息标题和内容作为参数，在具备WXPUSHER_TOKEN和WXPUSHER_USER_ID的情况下
# 通过curl命令向WxPusher API发送消息，并根据发送结果输出相应提示信息
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

# 发送 PUSHPLUS 消息的函数
# 接收消息标题和内容作为参数，在具备PUSHPLUS_TOKEN的情况下
# 通过curl命令向PushPlus API发送消息，并根据发送结果输出相应提示信息
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
        }" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        colorize green "PushPlus 消息发送成功"
    else
        colorize red "PushPlus 消息发送失败"
    fi
}

# 定义进程相关数组（对应不同服务进程及其友好名称）
# 用于在检查进程状态时将进程名转换为更易读的友好名称进行展示
declare -A processes=(
    ["singbox"]="Singbox"
    ["nezha-dashboard"]="哪吒面板"
    ["nezha-agent"]="哪吒探针 V1"
    ["sun-panel"]="Sun Panel"
    ["wssh"]="Web SSH"
    ["alist"]="Alist"
)

# 新增函数用于检查进程状态
# 接收服务器的用户名、密码和主机地址作为参数
# 通过ssh连接到服务器并获取进程列表，然后比对预设的服务进程是否存在
# 根据比对结果返回相应状态码，并输出相应提示信息
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
# 用于在输出信息中对敏感的用户名信息进行部分隐藏，增强安全性和隐私性
mask_username() {
    local username="$1"
    echo "****${username: -3}"
}

# 掩码处理函数：对服务器名进行掩码，只显示第一个字段（以.为分隔符）
# 同样用于在输出信息中对服务器名进行部分处理，隐藏不必要的详细信息
mask_server() {
    local server="$1"
    echo "$server" | cut -d '.' -f 1
}

# 处理服务器相关操作的主函数，包含检查服务目录、启动服务、检查进程状态等逻辑
# 接收服务器列表信息和通知服务配置作为参数，遍历服务器列表对每个服务器执行相关操作
# 并汇总各服务器操作情况生成消息内容，最后根据通知服务配置发送相应通知消息
handle_servers() {
    local servers="$1"
    local notify_service="$2"
    IFS=',' read -ra SERVER_LIST <<< "$servers"
    combined_message=""  # 用于汇总所有服务器执行情况的消息内容
    index=1  # 索引，用于记录处理的服务器序号

    # 结果摘要标题，用于构建最终发送的通知消息内容的开头部分
    RESULT_SUMMARY="青龙自动进程内容：\n———————————————————————\n SERV00 \n———————————————————————\n"
    combined_message="$RESULT_SUMMARY"

    for SERVER in "${SERVER_LIST[@]}"; do
        # 分解每个服务器的用户名、密码、地址
        IFS=':' read -r SSH_USER SSH_PASS SSH_HOST <<< "$SERVER"

        # 获取掩码后的用户名和服务器名，用于后续输出展示，增强信息安全性
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
                ssh_cmd+="cd $service_path || true; pkill -f '$service_name' || true; nohup./$service_name > /dev/null 2>&1 & "
                services_started+="$service_name "  # 服务以空格分隔
            else
                colorize red "目录不存在，跳过 $service_name 服务"
            fi
        }

        # 依次检查每个服务的目录并启动
        [[ "$SINGBOX" -eq 1 ]] && check_and_add_service "singbox" "/home/$SSH_USER/serv00-play/singbox"
        [[ "$NEZHA_DASHBOARD" -eq 1 ]] && check_and_add_service "nezha-dashboard" "/home/$SSH_USER/nezha_app/dashboard"
        [[ "$NEZHA_AGENT" -eq 1 ]] && check_and_add_service "nezha-agent" "/home/$SSH_USER/nezha_app/agent"
        [[ "$SUN_PANEL" -eq 1 ]] && check_and_add_service "sun-panel" "/home/$SSH_USER/serv00-play/sunpanel"
        [[ "$WEB_SSH" -eq 1 ]] && check_and_add_service "wssh" "/home/$SSH_USER/serv00-play/webssh"
        [[ "$ALIST" -eq 1 ]] && check_and_add_service "alist" "/home/$SSH_USER/serv00-play/alist"

        # 执行构建的 SSH 命令，在服务器上执行相应操作（如启动服务等）
        sshpass -p "$SSH_PASS" ssh -o LogLevel=QUIET -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" "$ssh_cmd"

        # 拼接服务启动后的状态信息到汇总消息内容中，使用掩码后的用户名和服务器名
        if [ -n "$services_started" ]; then
            colorize green "✅ $index. $MASKED_USERNAME 【 $MASKED_SERVER 】登录成功 \n 重启服务：$services_started\n——————————————————————"
            combined_message+="✅ $index. $MASKED_USERNAME 【 $MASKED_SERVER 】登录成功 \n 重启服务：$services_started\n———————————————————————\n"
        else
            colorize red "❌ $index. $MASKED_USERNAME 【 $MASKED_SERVER 】登录失败"
            combined_message+="❌ $index. $MASKED_USERNAME 【 $MASKED_SERVER 】 - 登录失败\n"
        fi
        index=$((index + 1))
    done

    # 根据通知服务配置发送通知消息，消息内容中的用户名和服务器名也是掩码后的
    if [ "$notify_service" -eq 1 ] || [ "$notify_service" -eq 4 ] || [ "$notify_service" -eq 5 ]; then
        send_tg_notification "$combined_message"
    fi
    if [ "$notify_service" -eq 2 ] || [ "$notify_service" -eq 4 ]; then
        send_wxpusher_message "VPS 自动进程内容" "$combined_message"
    fi
    if [ "$notify_service" -eq 3 ] || [ "$notify_service" -eq 5 ]; then
        send_pushplus_message "VPS 自动进程内容" "$combined_message"
    fi
}

# 主函数，用于调用其他函数，按照逻辑顺序执行脚本的主要流程
main() {
    handle_servers "$SERVERS" "$NOTIFY_SERVICE"
    colorize green "脚本执行完毕，通知已发送！"
}

main
