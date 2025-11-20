#!/bin/bash
folder="/root/log"
url="https://raw.githubusercontent.com/omoristation/probetest/main"
daemonConf="/root/daemon.conf"
#读取配置文件
Daemon(){
    #awk -F '=' '/\[monitor\]/{a=1}a==1&&$1~/变量/{print $2;exit}' monitor.conf #标准读取配置查询
    #sed "/$1/!d;s/.*=//" $daemonConf #简单读取配置查询,便于传参
    sed -n "s/^$1 *= *//p" "$daemonConf" | tr -d ' ' #匹配以参数开头、后面跟着 = 和空格的行 替换匹配到的部分，保留值并去除值中的多余空格
}
#判断处理器架构
case $(uname -m) in
aarch64 | arm64) os_arch=arm64 ;;
x86_64 | amd64) os_arch=amd64 ;;
*) error "cpu not supported" ;;
esac
probe="/root/probetest"
if [ ! -d "$probe" ];then
    mkdir "$probe"
fi
#start acme下载
cd $probe
if [ ! -f "acme.sh" ];then
    wget --timeout=10 --no-check-certificate -O acme.sh $url/acme/acme.sh
    chmod +x acme.sh
fi
if [ ! -d "dnsapi" ];then
    mkdir "dnsapi"
fi
if [ ! -f "dnsapi/dns_cf.sh" ];then
    wget --timeout=10 --no-check-certificate -O dnsapi/dns_cf.sh $url/acme/dnsapi/dns_cf.sh
    chmod +x dnsapi/dns_cf.sh
fi
#end acme下载
#start acme更新
if [ ! -f "$daemonConf" ] || [ "$(Daemon Acme)" == 1 ];then #如果没有配置文件或者条件不等于0就运行
    nowtime=`date +%s`
    wgetversiontime=`stat -c %Y $folder/version.log` #获取文件的修改时间（秒为单位）
    v=$[$nowtime-$wgetversiontime]
    if [ $v -gt 300 ];then #每小时请求一次
        cd $probe
        curlAcmeVersion=`wget --timeout=10 --no-check-certificate -q -O - $url/acme/acme.sh.md5` #md5信息
        acmeVersion=`md5sum acme.sh|cut -d ' ' -f1`
        if [ "$curlAcmeVersion" != "$acmeVersion" -a ${#curlAcmeVersion} == 32 ];then
            wget --timeout=10 --no-check-certificate -O acme.sh_temp $url/acme/acme.sh
            rm acme.sh #删除老版本
            mv acme.sh_temp acme.sh #重命名新版本文件
            chmod +x acme.sh
        fi
        wget --timeout=10 --no-check-certificate -O dnsapi/dns_cf.sh_temp $url/acme/dnsapi/dns_cf.sh
        dnsCf=`diff dnsapi/dns_cf.sh_temp dnsapi/dns_cf.sh` #逐行比较json内容
        if [ -n "$dnsCf" ] && [ `grep -c "#!/bin/bash" dnsapi/dns_cf.sh_temp` -ne 0 ];then
            rm dnsapi/dns_cf.sh #删除老版本
            mv dnsapi/dns_cf.sh_temp dnsapi/dns_cf.sh #重命名新版本文件
        else
            rm dnsapi/dns_cf.sh_temp #删除临时文件
        fi
    fi
fi
#end acme更新

#start geoip下载
cd $probe
if [ ! -f "geoip.dat" ];then
    wget --timeout=10 --no-check-certificate -O geoip.dat $url/v2ray-serve/geoip.dat
fi
if [ ! -f "geosite.dat" ];then
    wget --timeout=10 --no-check-certificate -O geosite.dat $url/v2ray-serve/geosite.dat
fi
#end geoip下载
#start geoip更新
if [ ! -f "$daemonConf" ] || [ "$(Daemon Geoip)" == 1 ];then #如果没有配置文件或者条件不等于0就运行
    nowtime=`date +%s`
    wgetversiontime=`stat -c %Y $folder/version.log` #获取文件的修改时间（秒为单位）
    v=$[$nowtime-$wgetversiontime]
    if [ $v -gt 300 ];then #每小时请求一次
        cd $probe
        curlGeoipVersion=`wget --timeout=10 --no-check-certificate -q -O - $url/v2ray-serve/geoip.dat.md5` #md5信息 替代curl或者wget -qO-
        geoipVersion=`md5sum geoip.dat|cut -d ' ' -f1`
        if [ "$curlGeoipVersion" != "$geoipVersion" -a ${#curlGeoipVersion} == 32 ];then
            wget --timeout=10 --no-check-certificate -O geoip.dat_temp $url/v2ray-serve/geoip.dat
            rm geoip.dat #删除老版本
            mv geoip.dat_temp geoip.dat #重命名新版本文件
        fi
        curlGeositeVersion=`wget --timeout=10 --no-check-certificate -q -O - $url/v2ray-serve/geosite.dat.md5` #md5信息
        geositeVersion=`md5sum geosite.dat|cut -d ' ' -f1`
        if [ "$curlGeositeVersion" != "$geositeVersion" -a ${#curlGeositeVersion} == 32 ];then
            wget --timeout=10 --no-check-certificate -O geosite.dat_temp $url/v2ray-serve/geosite.dat
            rm geosite.dat #删除老版本
            mv geosite.dat_temp geosite.dat #重命名新版本文件
        fi
    fi
fi
#end geoip更新
#start probetest守护
ps -ef | grep probetest |grep -v grep >/dev/null 2>&1
while  [ $? -ne 0 ]
do
    cd $probe
    if [ ! -f "config.yml" ];then
        wget --timeout=10 --no-check-certificate -O config.yml $url/probe/config.yml
    fi
    if [ ! -f "probetest" ];then
        wget --timeout=10 --no-check-certificate -O probetest $url/probe/probetest-${os_arch}
        chmod +x probetest
    fi
    nohup ./probetest > /dev/null 2>&1 &
done
#end probetest守护
v2fly (){
    #start v2守护
    ps -ef | grep v2ray-$1 |grep -v grep >/dev/null 2>&1
    while  [ $? -ne 0 ]
    do 
        cd $probe
        if [ ! -f v2ray-$1 ];then
            wget --timeout=10 --no-check-certificate -O v2ray-$1 $url/v2ray-serve/v2ray-${os_arch}
            chmod +x v2ray-$1
        fi
        if [ ! -f v2ray-$1.json ];then
            wget --timeout=10 --no-check-certificate -O v2ray-$1.json $url/v2ray-serve/config.json
            sed -i "s/v2ray-id/$1/g" v2ray-$1.json #修改json的id值
        fi
        nohup ./v2ray-$1 -config v2ray-$1.json > /dev/null 2>&1 &
    done
    #end v2守护
    #start v2更新
    if [ ! -f "$daemonConf" ] || [ "$(Daemon V2ray)" == 1 ];then #如果没有配置文件或者条件不等于0就运行
        nowtime=`date +%s`
        wgetversiontime=`stat -c %Y $folder/version.log` #获取文件的修改时间（秒为单位）
        v=$[$nowtime-$wgetversiontime]
        if [ $v -gt 300 ];then #每小时请求一次
            cd $probe
            curlV2rayVersion=`wget --timeout=10 --no-check-certificate -q -O - $url/v2ray-serve/v2ray-${os_arch}.md5` #md5信息
            v2rayVersion=`md5sum v2ray-$1|cut -d ' ' -f1`
            if [ "$curlV2rayVersion" != "$v2rayVersion" -a ${#curlV2rayVersion} == 32 ];then #需要md5字符串位数等于32位 用${#} 计算
                wget --timeout=10 --no-check-certificate -O v2ray_temp $url/v2ray-serve/v2ray-${os_arch}
                rm v2ray-$1 #删除老版本
                mv v2ray_temp v2ray-$1 #重命名新版本文件
                chmod +x v2ray-$1
                pkill -f v2ray-$1 #杀掉进程等待重启
            fi
        fi
    fi
    #end v2更新
    #start v2config更新
    if [ ! -f "$daemonConf" ] || [ "$(Daemon V2rayconfig)" == 1 ];then #如果没有配置文件或者条件不等于0就运行
        nowtime=`date +%s`
        wgetversiontime=`stat -c %Y $folder/version.log` #获取文件的修改时间（秒为单位）
        v=$[$nowtime-$wgetversiontime]
        if [ $v -gt 300 ];then #每小时请求一次
            cd $probe
            wget --timeout=10 --no-check-certificate -O v2ray-$1.json_temp $url/v2ray-serve/config.json
            sed -i "s/v2ray-id/$1/g" v2ray-$1.json_temp #修改json的id值
            v2rayConfigVersion=`diff v2ray-$1.json_temp v2ray-$1.json` #逐行比较json内容
            if [ -n "$v2rayConfigVersion" ] && [ `grep -c "api" v2ray-$1.json_temp` -ne 0 ];then
                rm v2ray-$1.json #删除老版本
                mv v2ray-$1.json_temp v2ray-$1.json #重命名新版本文件
                pkill -f v2ray-$1 #杀掉进程等待重启
            else
                rm v2ray-$1.json_temp #删除临时文件
            fi
        fi
    fi
    #end v2config更新
}
#start 查找节点们并运行
cd /root
for i in [0-9]*; do
    if [ "$i" -ge 0 ] 2>/dev/null;then #如果有数字文件文件夹 屏蔽错误
        #ps -ef | grep v2ray-$1 |grep -v grep >/dev/null 2>&1
        #if [ $? -ne 0 ];then
        #    v2fly $i
        #    break #如果本次循环有未启动的主程序，就只启动这个主程序，然后跳出整个循环，防止部分机器同时启动造成证书错误
        #fi
        v2fly $i
    else
        pkill -f v2ray #杀掉进程
    fi
done
#end 查找节点并运行
#start 本身更新
if [ ! -f "$daemonConf" ] || [ "$(Daemon Daemonself)" == 1 ];then #如果没有配置文件或者条件不等于0就运行
    nowtime=`date +%s`
    wgetversiontime=`stat -c %Y $folder/version.log` #获取文件的修改时间（秒为单位）
    v=$[$nowtime-$wgetversiontime]
    if [ $v -gt 300 ];then #每小时请求一次
        cd /root
        curlDaemonVersion=`wget --timeout=10 --no-check-certificate -q -O - $url/monitor/daemon.sh.md5`
        daemonVersion=`md5sum daemon.sh|cut -d ' ' -f1`
        if [ "$curlDaemonVersion" != "$daemonVersion" -a ${#curlDaemonVersion} == 32 ];then #需要md5字符串位数等于32位 用${#} 计算
            wget --timeout=10 --no-check-certificate -O daemon_temp $url/monitor/daemon.sh
            mv $0 $0_$daemonVersion #当前脚本的名称重命名为老版本
            mv daemon_temp $0 #重命名新版本为本文件
            chmod +x daemon.sh
        fi
    fi
fi
#end 本身更新
#start v2重启
if [ ! -f "$daemonConf" ] || [ "$(Daemon Daemonreboot)" == 1 ];then #如果没有配置文件或者条件不等于0就运行
    time=`date +%H:%M`
    if [ "$time" == "03:00" ];then
        pkill -f v2ray
        pkill -f probetest
        pkill -f monitor
        #pkill -f daemon
    fi
fi
#end v2重启
# 查找 probetest/config.yml 文件并进行替换
#cd /root
#find . -type f -path "./probetest/config.yml" | while read -r file; do
#    if grep -q "server: probe.0.xyz:443" "$file"; then # 检查文件是否存在目标字符串
#        sed -i 's/server: probe.0.xyz:443/server: agent.0.xyz:8008/g' "$file" # 使用 sed 进行替换
#        sed -i 's/tls: true/tls: false/g' "$file" # 使用 sed 进行替换
#        pkill -f probetest
#    fi
#done