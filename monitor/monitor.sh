#!/bin/bash
url="https://raw.githubusercontent.com/omoristation/probetest/main"
#start 报警邮件
#设置日志目录(后面不要有/)
folder="/root/log"
monitorConf="/root/monitor.conf"
if [ ! -d "$folder" ]; then
    mkdir "$folder"
fi
#status=2赋值前为空时设为2 ，防止报错
declare -i status=2
curlip=$(echo "$(wget --timeout=10 --no-check-certificate --inet4-only -q -O - https://vpng.net)") #获取ip 只使用ipv4 --inet4-only https://ipinfo.io/ip
if [ ! -f "$folder/ip.log" ]; then
    echo $curlip > $folder/ip.log
fi
nowtime=`date +%s`
curliptime=`stat -c %Y $folder/ip.log` #获取文件的修改时间（秒为单位）
v=$[$nowtime-$curliptime]
if [ $v -gt 3600 ]; then #每小时请求一次
    if [ -z "$curlip" ]; then # 判断 curlip 是否为空
        curlip=$(echo "$(wget --timeout=10 --no-check-certificate -q -O - https://vpng.net)") # 如果为空，重新请求
    fi
    hostnamefile=$(ls hostname.* 2>/dev/null) #查找符合条件的文件
    hostname="${hostnamefile##*.}" #提取文件的后缀
    echo $hostname-$curlip > $folder/ip.log
fi
ip=`cat $folder/ip.log` #读取ip
#读取配置文件
Monitorconf(){
    #awk -F '=' '/\[monitor\]/{a=1}a==1&&$1~/变量/{print $2;exit}' monitor.conf #标准读取配置查询
    #sed "/$1/!d;s/.*=//" $monitorConf #简单读取配置查询,便于传参
    sed -n "s/^$1 *= *//p" "$monitorConf" | tr -d ' ' #匹配以参数开头、后面跟着 = 和空格的行 替换匹配到的部分，保留值并去除值中的多余空格
}
#自动更新
UpdateMonitor () {
    if [ ! -f "$monitorConf" ] || [ "$(Monitorconf Updatesend)" == 1 ]; then #判断要有空格#如果没有配置文件或者条件不等于0就运行
        update() {
            curlMonitorVersion=`wget --timeout=10 --no-check-certificate -q -O - $url/monitor/monitor.sh.md5` #md5信息
            monitorVersion=`md5sum monitor.sh|cut -d ' ' -f1`
            if [ "$curlMonitorVersion" != "$monitorVersion" -a ${#curlMonitorVersion} == 32 ];then #需要md5字符串位数等于32位 用${#} 计算
                wget --timeout=10 --no-check-certificate -O monitor_temp $url/monitor/monitor.sh
                mv $0 $0_$monitorVersion #当前脚本的名称重命名为老版本
                mv monitor_temp $0 #重命名新版本为本文件
            fi
            echo $curlMonitorVersion > $folder/version.log
            #exec "$0" "$@" #重启本身脚本
        }
        if [ ! -f "$folder/version.log" ]; then
            update
        else
            nowtime=`date +%s`
            wgetversiontime=`stat -c %Y $folder/version.log` #获取文件的修改时间（秒为单位）
            v=$[$nowtime-$wgetversiontime]
            if [ $v -gt 360 ]; then #每小时请求一次 这里的间隔时间一点要比daemon.sh的版本更新间隔时间多一点，但不能超过2倍，不然daemon.sh永远获取不到更新或者更新多次
                update
            else
                echo "UpdateMonitor OK"
                status=2
            fi
        fi
    else
        echo "UpdateMonitor OK"
        status=2
    fi
}
#监控进程守护
DaemonMonitor () {
    if [ ! -f "$monitorConf" ] || [ "$(Monitorconf Daemonsend)" == 1 ]; then
        if [ ! -f "daemon.sh" ]; then #如果守护文件不存在,就忽略
            echo "DaemonMonitor OK"
            status=2
        else
            ps -ef | grep daemon.sh |grep -v grep >/dev/null 2>&1
            while [ $? -ne 0 ]; do 
                bash daemon.sh >/dev/null 2>&1
            done
        fi
    fi
}
#监控用户登录
UserMonitor () {
    if [ ! -f "$monitorConf" ] || [ "$(Monitorconf Usersend)" == 1 ]; then
        LoginUser=`who | grep pts | wc -l`
        #sshname=$(who | awk '{print $5}' | sed 's/[()]//g') # 获取ssh登录者IP
        sshname=$(who | grep pts | sed 's/^.*(\(.*\)).*/\1/') # 获取ssh登录者IP 替换括号之前和之后的内容为空 例如 root pts/0 2024-04-24 21:02 (133.130.167.16)
        if [ -z "$sshname" ]; then
            sshname=$(echo $SSH_CONNECTION | awk '{print $1}') # 获取ssh登录者IP 需要.profile文件调用本脚本
        fi
        if [ $LoginUser -ge 2 ]; then
            WarningT="登录报警[$ip]"
            Warning="登录报警[$ip],系统登录多用户为[$LoginUser]人,请确认。"
            status=0
        elif [ -n "$sshname" ] && [ "$sshname" != "127.0.0.1" ]; then # 如果ssh登录
            dynamicip=$(echo "$(wget --no-cache --timeout=10 --no-check-certificate -q -O - https://vpng.net/?ip=1.dynamic.owlvpn.net)" | awk '{print $1}') # 使用 awk 提取第一个空格之前的部分 例"1.33.242.181 jp 日本" 禁用wget缓存
            sship=$(echo "$(wget --no-cache --timeout=10 --no-check-certificate -q -O - https://vpng.net/?ip=$sshname)" | awk '{print $1}') #考虑反向dns有域名的情况，先解析一下
            if [ "$sship" != "$dynamicip" ]; then
                wgetip=$(echo "$(wget --no-cache --timeout=10 --no-check-certificate -q -O - https://vpng.net/?ip=$sshname)")
                WarningT="登录报警[$ip]"
                Warning="登录报警[$ip],系统登录非法用户为[$wgetip],请确认。"
                status=0
            fi
        else
            echo "UserMonitor OK"
            status=2
        fi
    fi
}
#监控DDOS攻击
DdosMonitor () {
    if [ ! -f "$monitorConf" ] || [ "$(Monitorconf Ddossend)" == 1 ]; then
        /bin/netstat -na|grep ESTABLISHED|awk '{print $5}'|awk -F: '{print $1}'|sort|uniq -c|sort -rn|head -10|grep -v -E '192.168|127.0'|awk '{if ($2!=null && $1>100) {print $2}}'>$folder/dropip   #100为已建立的连接数，根据需要修改
        for i in $(cat $folder/dropip); do
            /sbin/iptables -A INPUT -s $i -j DROP #临时加入防火墙黑名单，重启防火墙或者系统失效
            echo "$i kill at `date`">>$folder/ddos
        done
        ddos=`$folder/dropip | wc -l`
        if  [ $ddos -ge 1 ]; then
            WarningT="攻击报警[$ip]"
            Warning="攻击报警[$ip],攻击ip为[$ddos]个,请确认。"
            status=0
        elif [ $ddos -eq 1 ]; then
            WarningT="攻击警告[$ip]"
            Warning="攻击警告[$ip],攻击ip为[$ddos]个，请及时处理。"
            status=0
        else
            echo "DdosMonitor OK"
            status=2
        fi
    fi
}
#监控内存
MemMonitor () {
    if [ ! -f "$monitorConf" ] || [ "$(Monitorconf Memsend)" == 1 ]; then
        MemTotal=`free -m | grep Mem | awk -F: '{print $2}' | awk '{print $1}'`
        #MemFree=`free -m | grep cache | awk NR==2 | awk '{print $4}'`
        MemFree=`free -m | grep Mem | awk -F: '{print $2}' | awk '{print $1-$2}'`   #centos7
        #MemFreeB=`awk 'BEGIN{printf "%d\n",'$MemFree/$MemTotal\*100'}'`
        MemFreeS=`awk 'BEGIN{printf "%.f",'$MemFree/$MemTotal\*100'}'`
        if [ $MemFreeS -lt 5 ]; then
            WarningT="内存报警[$ip]"
            Warning="内存报警[$ip],系统真实可用内存为[$MemFreeS]%，请立即处理。"
            status=0
        elif [ $MemFreeS -lt 10 ]; then
            WarningT="内存警告[$ip]"
            Warning="内存警告[$ip],系统真实可用内存为[$MemFreeS]%，请及时处理。"
            status=0
        else
            echo "MemMonitor OK"
            status=2
        fi
    fi
}
#监控硬盘容量
DiskMonitor () {
    if [ ! -f "$monitorConf" ] || [ "$(Monitorconf Disksend)" == 1 ]; then
        DiskGA=`df | awk '{print $5}' | grep -c -E "^[9-9][0-5]"` #统计使用率90-95%的分区有几个
        DiskGB=`df | awk '{print $5}' | grep -c -E "^[9-9][5-9]|^100"` #统计使用率95-99或者100%的分区有几个
        DiskGS=`df | awk '{print $1" "$5" "$6}' | grep -E "[9-9][0-5]%" | sed 's/[ ][ ]*/|/g' | tr "\n" "|"` #打印出使用率90-95%的分区信息,替换空格和换行为'|',避免TG不能发送空行空格导致漏发 
        DiskGT=`df | awk '{print $1" "$5" "$6}' | grep -E "[9-9][5-9]%|100%" | sed 's/[ ][ ]*/|/g' | tr "\n" "|"` #打印出使用率95-99或者100%的分区信息,替换空格和换行为'|',避免TG不能发送空行空格导致漏发 
        if [ $DiskGB -gt 0 ]; then 
            WarningT="硬盘容量报警[$ip]"
            Warning="硬盘容量报警[$ip],硬盘使用率[$DiskGT]，请立即处理。"
            status=0
        elif [ $DiskGA -gt 0 ]; then
            WarningT="硬盘容量警告[$ip]"
            Warning="硬盘容量警告[$ip],硬盘使用率[$DiskGS]，请及时处理。"
            status=0
        else
            echo "DiskMonitor OK"
            status=2
        fi
    fi
}
#监控CPU负载
CPULoad () {
    if [ ! -f "$monitorConf" ] || [ "$(Monitorconf Cpusend)" == 1 ]; then
        CPULoad1=`cat /proc/loadavg | awk '{printf "%d\n",$1}'`
        CPULoad2=`cat /proc/loadavg` #此处TG只能发送第一列数字,不影响阅读
        if [ $CPULoad1 -ge 10 ]; then
            WarningT="CPU负载报警[$ip]"
            Warning="CPU负载报警[$ip],CPU负载为[$CPULoad2]，请立即处理。"
            status=0
        elif [ $CPULoad1 -ge 5 -a $CPULoad1 -lt 10 ]; then
            WarningT="CPU负载警告[$ip]"
            Warning="CPU负载警告[$ip],CPU负载为[$CPULoad2]，请及时处理。"
            status=0
        else
            echo "CPULoad OK"
            status=2
        fi
    fi
}
#监控网速
NetworkSpeed () {
    if [ ! -f "$monitorConf" ] || [ "$(Monitorconf Speedsend)" == 1 ]; then
        #借写空值到文件重置网速记录
        echo "" > $folder/network_traffic.txt
        #获取网卡流量,为Transmit发送流量
        inet_byte() {
            for i in `ls /sys/class/net/`; do
                #和下面的可以二选一 let "$i"_tx"$1"=`cat /sys/class/net/$i/statistics/tx_bytes`
                eval "$i"_tx"$1"=`cat /proc/net/dev | grep $i | tr : " " | awk '{print $10}'` #let是专门计算的，但是不兼容个别系统，就用了更为激进的 eval
            done
        }
        #打印平均流量到文件
        eva() {
            b1=`eval echo '$'"$1"_tx1`
            b2=`eval echo '$'"$1"_tx2`
            #只显示平均网速大于1M/s的网卡 #当前30秒平均流量，以防单一秒内瞬时流量骤增，导致误判#取网速为整数
            txMB=$(echo $b2 $b1 | awk '{if(($1-$2)/1048576/30 > 1) printf "%d\n" ,($1-$2)/1048576/30}')
            echo "tx:$txMB" >> $folder/network_traffic.txt
        }
        #可以设定循环次数及时长，取30秒钟的平均网速
        int=1
        while (( $int>=1 )); do
            int=$(($int - 1));
            inet_byte 1
            sleep 30
            inet_byte 2
            for i in `ls /sys/class/net/`; do
                eva $i
            done
        done
        #traffic赋值前为空时设为0 ，防止报错
        declare -i traffic=0
        #截取流量平均值数字,去掉空行
        traffic=`tail $folder/network_traffic.txt | grep 'tx:' | cut -d: -f2 | grep -v '^$' | awk '{print $1*8}'`
        #traffic=`tail $folder/network_traffic.txt | grep -o 'tx:[0-9]*' | cut -d: -f2`
        #设定网速报警阀值单位*M/s #网速报警控制开关
        if [ $traffic -ge 120 ]; then
            WarningT="网速监控报警[$ip]"
            Warning="网速监控报警[$ip],网速[$traffic]Mbps，请立即处理。"
            status=0
        elif [ $traffic -ge 100 -a $traffic -lt 120 ]; then
            WarningT="网速监控警告[$ip]"
            Warning="网速监控警告[$ip],网速[$traffic]Mbps，请及时处理。"
            status=0
        else
            echo "NetworkSpeed OK"
            status=2
        fi
    fi
}
#几个模块循环发送报警短信、报警邮件
for n in UpdateMonitor DaemonMonitor UserMonitor DdosMonitor MemMonitor DiskMonitor CPULoad NetworkSpeed; do
    #写日志
    exec 1>>$folder/monitor.log 2>>$folder/monitor_err.log
    $n
    if [ $status -eq 0 ]; then
        #报警通知频率清洗：一小时之内每隔10分钟发一次
        #先建好时间基准文件和循环次数文件好用来对比
        if [ ! -f "$folder/timestamp.log" ]; then
            echo "0" > $folder/timestamp.log
        fi
        if [ ! -f "$folder/number.log" ]; then
            echo "0" > $folder/number.log
        fi
        if [ ! -f "$folder/number_minutes.log" ]; then
            echo "0" > $folder/number_minutes.log
        fi
        if [ ! -f "$folder/number_hours.log" ]; then
            echo "0" > $folder/number_hours.log
        fi
        nu=`cat $folder/number.log` #每分钟计数
        nu_m=`cat $folder/number_minutes.log` #每10分钟计数
        nu_h=`cat $folder/number_hours.log` #每小时计数
        t_s1=`date +%s`
        t_s2=`tail -1 $folder/timestamp.log`
        curlhttp(){
            #curl http://mail.zx.net/ -d "who=$1&fromname=$2&toemail=$3&title=$4&content=$5"
            #curl -s -X POST https://api.owlvpn.net/telegram/ -F who=$1 -F fromname=$2 -F toemail=$3 -F title=$4 -F content=$5 #发telegram 只能使用post才能成功 用wget替代
            #wget --method=POST --body-data="who=$1&fromname=$2&toemail=$3&title=$4&content=$5" -q -O - https://api.owlvpn.net/telegram/
            wget --post-data="who=$1&fromname=$2&toemail=$3&title=$4&content=$5" --timeout=10 --no-check-certificate -q -O - https://api.owlvpn.net/telegram/
        }
        v=$[$t_s1-$t_s2]
        if [ $v -gt 7200 ]; then #离动作大于2小时后触发
            #curlhttp 4 monitor 131@139.com $WarningT $Warning
            curlhttp 0 monitor -279362737 "$WarningT" "$Warning"
            echo `date +%s` > $folder/timestamp.log #写入触发时的时间戳
            echo "0" > $folder/number_hours.log #超过1小时的 小时计数清零
            echo "0" > $folder/number_minutes.log #超过1小时的 10分钟计数清零
        else
            nu=$[$nu+1]
            echo $nu > $folder/number.log #每分钟增加
            if [ $nu -ge 10 ]; then
                nu_m=$[$nu_m+1]
                echo $nu_m > $folder/number_minutes.log #每10分钟增加
                if [ $nu_h -eq 0 -a $nu_m -lt 6 ]; then #小于一小时内触发
                    #curlhttp 4 monitor 131@139.com $WarningT缓10分 $Warning
                    curlhttp 0 monitor -279362737 "$WarningT缓10分" "缓10分$Warning"
                    echo `date +%s` > $folder/timestamp.log #写入触发时的时间戳
                fi
                echo "0" > $folder/number.log #分钟计数清零
                if [ $nu_m -ge 6 ]; then #在第60分钟触发
                    #curlhttp 4 monitor 131@139.com $WarningT_缓1时 $Warning
                    curlhttp 0 monitor -279362737 "$WarningT缓1时" "缓1时$Warning"
                    echo `date +%s` > $folder/timestamp.log #写入触发时的时间戳
                    nu_h=$[$nu_h+1]
                    echo $nu_h > $folder/number_hours.log #每1小时增加
                    echo "0" > $folder/number_minutes.log #10分钟计数清零
                fi
            fi
        fi
    elif [ $status -eq 1 ]; then #报警通知$status设置为1时跳过通知频率清洗
        #curlhttp 4 monitor 147@139.com,131@139.com,187@139.com $WarningT $Warning
        curlhttp 0 monitor -279362737,-279362737 "$WarningT" "$Warning"
    else
        echo "OK"
    fi
done
#end 报警邮件
