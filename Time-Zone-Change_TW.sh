#!/bin/bash
# Debian 時間與時區管理工具 (繁體中文版)
# 功能：時區設定、NTP 伺服器管理、中文時區顯示
# 最後更新：2025-08-07

# 檢查 root 權限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[31m錯誤：此操作需要 root 權限！\033[0m"
        echo "請使用 sudo 執行此腳本"
        exit 1
    fi
}

# 繁體中文時區映射表
declare -A tz_cn_map=(
    ["Asia/Taipei"]="台北"
    ["Asia/Hong_Kong"]="香港"
    ["Asia/Macau"]="澳門"
    ["Asia/Shanghai"]="上海"
    ["Asia/Tokyo"]="東京"
    ["Asia/Seoul"]="首爾"
    ["Asia/Singapore"]="新加坡"
    ["America/New_York"]="紐約"
    ["America/Los_Angeles"]="洛杉磯"
    ["Europe/London"]="倫敦"
    ["Europe/Paris"]="巴黎"
    ["Europe/Berlin"]="柏林"
    ["Australia/Sydney"]="雪梨"
)

# 顯示繁體中文時區名稱
get_tz_cn_name() {
    local tz="$1"
    if [ -n "${tz_cn_map[$tz]}" ]; then
        echo "${tz_cn_map[$tz]}"
    else
        # 從時區ID提取城市名
        local city=$(echo "$tz" | awk -F '/' '{print $NF}' | tr '_' ' ')
        echo "$city"
    fi
}

# 顯示當前時區資訊
show_current_time() {
    echo -e "\n\033[34m■ 當前時區資訊:\033[0m"
    timedatectl | grep --color=always "Time zone\|Local time"
    echo -e "系統時鐘: $(date +'%Y-%m-%d %H:%M:%S %Z (%:z)')"
    
    # 顯示當前 NTP 伺服器
    local ntp_servers=$(grep '^NTP=' /etc/systemd/timesyncd.conf 2>/dev/null | cut -d= -f2)
    if [ -z "$ntp_servers" ]; then
        ntp_servers="(系統預設)"
    fi
    echo -e "NTP 伺服器: \033[35m$ntp_servers\033[0m"
}

# 列出可用時區 (中文加強版)
list_timezones() {
    local filter="$1"
    echo -e "\n\033[34m■ 常用時區清單 (中英對照):\033[0m"
    
    # 顯示常用時區 (帶中文名稱)
    for tz in "${!tz_cn_map[@]}"; do
        if [ -z "$filter" ] || [[ "$tz" =~ $filter ]] || [[ "${tz_cn_map[$tz]}" =~ $filter ]]; then
            printf "  \033[32m%-25s\033[0m %-15s %s\n" "$tz" "(${tz_cn_map[$tz]})"
        fi
    done
    
    echo -e "\n\033[34m■ 完整時區清單 (按 Q 退出):\033[0m"
    # 完整時區列表
    if [ -z "$filter" ]; then
        timedatectl list-timezones | less
    else
        timedatectl list-timezones | grep -i "$filter" | less
    fi
}

# 設定時區
set_timezone() {
    local tz="$1"
    
    # 驗證時區有效性
    if ! timedatectl list-timezones | grep -qx "$tz"; then
        echo -e "\033[31m錯誤：無效時區 '$tz'！\033[0m"
        return 1
    fi
    
    # 取得中文名稱
    local cn_name=$(get_tz_cn_name "$tz")
    
    echo -e "\n設定時區為: \033[32m$cn_name ($tz)\033[0m"
    timedatectl set-timezone "$tz"
    
    # 顯示設定結果
    echo -e "\n\033[32m✓ 時區設定成功！\033[0m"
    show_current_time
}

# 管理 NTP 時間同步
manage_ntp() {
    local action="$1"
    
    case "$action" in
        on)
            timedatectl set-ntp true
            systemctl restart systemd-timesyncd >/dev/null 2>&1
            echo -e "\033[32m✓ NTP 時間同步已啟用\033[0m"
            ;;
        off)
            timedatectl set-ntp false
            systemctl stop systemd-timesyncd >/dev/null 2>&1
            echo -e "\033[33m⚠ NTP 時間同步已停用\033[0m"
            ;;
        status)
            ntp_status=$(timedatectl | grep "NTP service" | awk '{print $3}')
            echo -e "NTP 狀態: \033[35m$ntp_status\033[0m"
            
            # 顯示當前 NTP 伺服器
            local ntp_servers=$(grep '^NTP=' /etc/systemd/timesyncd.conf 2>/dev/null | cut -d= -f2)
            if [ -z "$ntp_servers" ]; then
                echo "NTP 伺服器: (系統預設)"
            else
                echo "NTP 伺服器: $ntp_servers"
            fi
            ;;
        *)
            echo -e "\033[31m錯誤：無效操作！使用 'on' 或 'off'\033[0m"
            return 1
    esac
}

# 設定自訂 NTP 伺服器
set_custom_ntp() {
    echo -e "\n\033[36m請輸入 NTP 伺服器地址 (多個伺服器用空格分隔):\033[0m"
    echo "範例: ntp.ntu.edu.tw time.google.com pool.ntp.org"
    echo "輸入空白則恢復系統預設設定"
    read -p "> " ntp_servers
    
    # 確保設定檔存在
    if [ ! -f /etc/systemd/timesyncd.conf ]; then
        touch /etc/systemd/timesyncd.conf
    fi
    
    if [ -z "$ntp_servers" ]; then
        echo -e "\033[33m⚠ 恢復系統預設 NTP 設定\033[0m"
        # 刪除自訂設定，恢復預設
        sed -i '/^NTP=/d' /etc/systemd/timesyncd.conf
    else
        # 備份原始設定
        cp /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.bak 2>/dev/null
        
        # 更新設定檔
        if grep -q '^NTP=' /etc/systemd/timesyncd.conf; then
            sed -i "s/^NTP=.*/NTP=$ntp_servers/" /etc/systemd/timesyncd.conf
        else
            echo -e "\n[Time]\nNTP=$ntp_servers" >> /etc/systemd/timesyncd.conf
        fi
        echo -e "\n\033[32m✓ NTP 伺服器已設定為: $ntp_servers\033[0m"
    fi
    
    # 重啟服務
    systemctl restart systemd-timesyncd >/dev/null 2>&1
    timedatectl set-ntp true
    echo -e "\033[32mNTP 服務已重新啟動\033[0m"
}

# 顯示推薦的 NTP 伺服器
show_recommended_ntp() {
    echo -e "\n\033[36m■ 推薦的 NTP 伺服器清單:\033[0m"
    echo -e "\033[33m台灣地區:\033[0m"
    echo "  ntp.ntu.edu.tw      - 台灣大學"
    echo "  time.stdtime.gov.tw - 國家時間與頻率標準實驗室"
    echo "  watch.stdtime.gov.tw"
    echo "  clock.stdtime.gov.tw"
    echo "  tick.stdtime.gov.tw"
    
    echo -e "\n\033[33m國際公共伺服器:\033[0m"
    echo "  time.google.com     - Google 公共 NTP"
    echo "  time.windows.com    - Microsoft 時間伺服器"
    echo "  time.apple.com      - Apple 時間伺服器"
    echo "  pool.ntp.org        - 全球 NTP 池計畫"
    
    echo -e "\n\033[33m亞洲地區:\033[0m"
    echo "  ntp.nict.jp         - 日本國家情報通信研究機構"
    echo "  time.kriss.re.kr    - 韓國標準科學研究院"
    echo "  ntp.sjtu.edu.cn     - 上海交通大學"
    
    echo -e "\n\033[33m企業自建建議:\033[0m"
    echo "  建議至少設定 3 個不同來源的 NTP 伺服器"
    echo "  範例："
    echo "    ntp.ntu.edu.tw time.google.com pool.ntp.org"
}

# 互動式選單
interactive_menu() {
    while true; do
        clear
        echo -e "\n\033[44m Debian 時間與時區管理工具 (繁體中文版) \033[0m\n"
        show_current_time
        echo -e "\n\033[34m請選擇操作：\033[0m"
        echo " 1) 顯示當前時區資訊"
        echo " 2) 列出常用時區 (中英對照)"
        echo " 3) 搜尋特定時區 (例: Asia 或 台北)"
        echo " 4) 設定系統時區"
        echo " 5) 啟用 NTP 時間同步"
        echo " 6) 停用 NTP 時間同步"
        echo " 7) 顯示 NTP 狀態與伺服器"
        echo " 8) 設定自訂 NTP 伺服器"
        echo " 9) 顯示推薦 NTP 伺服器"
        echo "10) 離開"
        
        read -p "輸入選項 (1-10): " choice
        
        case $choice in
            1) 
                show_current_time
                ;;
            2) 
                list_timezones
                ;;
            3) 
                read -p "輸入時區關鍵字 (中英文皆可): " filter
                list_timezones "$filter"
                ;;
            4)
                echo -e "\n\033[36m請輸入時區名稱 (按 Enter 查看清單):\033[0m"
                read -p "時區 (e.g. Asia/Taipei): " tz
                if [ -z "$tz" ]; then
                    list_timezones
                else
                    set_timezone "$tz"
                fi
                ;;
            5) 
                manage_ntp on
                ;;
            6) 
                manage_ntp off
                ;;
            7) 
                manage_ntp status
                ;;
            8) 
                set_custom_ntp
                ;;
            9) 
                show_recommended_ntp
                ;;
            10) 
                echo -e "\n\033[32m✓ 操作完成。再見！\033[0m"
                exit 0
                ;;
            *) 
                echo -e "\033[31m錯誤：無效選項！\033[0m" 
                ;;
        esac
        
        read -n 1 -s -r -p "按任意鍵繼續..."
    done
}

# 主執行流程
if [ $# -eq 0 ]; then
    check_root
    interactive_menu
else
    case "$1" in
        "-i"|"--interactive")
            check_root
            interactive_menu
            ;;
        "-s"|"--show")
            show_current_time
            ;;
        "-l"|"--list")
            list_timezones "$2"
            ;;
        "-t"|"--set")
            check_root
            if [ -z "$2" ]; then
                echo -e "\033[31m錯誤：請指定時區名稱\033[0m"
                echo "範例: $0 --set Asia/Taipei"
                exit 1
            fi
            set_timezone "$2"
            ;;
        "-n"|"--ntp")
            check_root
            if [ -z "$2" ]; then
                echo -e "\033[31m錯誤：請指定操作 [on|off|status]\033[0m"
                echo "範例: $0 --ntp on"
                exit 1
            fi
            manage_ntp "$2"
            ;;
        "--set-ntp")
            check_root
            shift
            if [ $# -eq 0 ]; then
                set_custom_ntp
            else
                ntp_servers="$*"
                # 更新設定檔
                if grep -q '^NTP=' /etc/systemd/timesyncd.conf 2>/dev/null; then
                    sed -i "s/^NTP=.*/NTP=$ntp_servers/" /etc/systemd/timesyncd.conf
                else
                    echo -e "\n[Time]\nNTP=$ntp_servers" >> /etc/systemd/timesyncd.conf
                fi
                # 重啟服務
                systemctl restart systemd-timesyncd >/dev/null 2>&1
                timedatectl set-ntp true
                echo -e "\033[32m✓ NTP 伺服器已設定為: $ntp_servers\033[0m"
            fi
            ;;
        "-h"|"--help")
            echo -e "\n\033[36mDebian 時間與時區管理工具使用說明\033[0m"
            echo "用法: sudo $0 [選項]"
            echo ""
            echo "選項:"
            echo "  -i, --interactive   進入互動式選單 (預設)"
            echo "  -s, --show          顯示當前時區資訊"
            echo "  -l, --list [FILTER] 列出時區(可選過濾)"
            echo "  -t, --set TIMEZONE  設定時區 (需root)"
            echo "  -n, --ntp CMD       管理NTP同步 (on|off|status) (需root)"
            echo "      --set-ntp [SRV] 設定自訂NTP伺服器 (需root)"
            echo "  -h, --help          顯示幫助訊息"
            echo ""
            echo "範例:"
            echo "  sudo $0 -t Asia/Taipei"
            echo "  sudo $0 --set-ntp \"ntp.ntu.edu.tw time.google.com\""
            echo "  sudo $0 -n on"
            ;;
        *)
            echo -e "\033[31m錯誤：無效參數！\033[0m"
            echo "使用 $0 --help 查看幫助"
            exit 1
            ;;
    esac
fi