#!/bin/bash 

apt-get update
echo y |apt-get upgrade
echo y |apt-get install vim git python pkg-config libsodium-dev libssl-dev obfsproxy curl libc-ares-dev
echo y |apt-get install --no-install-recommends build-essential autoconf libtool libpcre3-dev libudns-dev libev-dev asciidoc xmlto automake

echo -e "#!/bin/sh\n ulimit -n 51200" > /etc/profile.d/limit.sh

echo -e "fs.file-max = 51200\n \
\n\
net.core.rmem_max = 67108864\n\
net.core.wmem_max = 67108864\n\
net.core.netdev_max_backlog = 250000\n\
net.core.somaxconn = 4096\n\
net.ipv4.tcp_syncookies = 1\n\
net.ipv4.tcp_tw_reuse = 1\n\
net.ipv4.tcp_tw_recycle = 0\n\
net.ipv4.tcp_fin_timeout = 30\n\
net.ipv4.tcp_keepalive_time = 1200\n\
net.ipv4.ip_local_port_range = 10000 65000\n\
net.ipv4.tcp_max_syn_backlog = 8192\n\
net.ipv4.tcp_max_tw_buckets = 5000\n\
net.ipv4.tcp_fastopen = 3\n\
net.ipv4.tcp_mem = 25600 51200 102400\n\
net.ipv4.tcp_rmem = 4096 87380 67108864\n\
net.ipv4.tcp_wmem = 4096 65536 67108864\n\
net.ipv4.tcp_mtu_probing = 1\n" > /etc/sysctl.d/99-ss.conf

if [[ -n `grep "net.core.default_qdisc" /etc/sysctl.conf`  ]]
then
    sed -i 's/net.core.default_qdisc=*/net.core/default_qdisc=fq/g' /etc/sysctl.conf
else
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
fi
if [[ -n `grep "net.ipv4.tcp_congestion_control" /etc/sysctl.conf` ]]
then
    sed -i 's/net.ipv4.tcp_congestion_control=.*/net.ipv4.tcp_congestion_control=bbr/g' /etc/sysctl.conf
else
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi

if [[ -z `grep "soft nofile" /etc/security/limits.conf` ]]
then
    echo -e "* soft nofile 51200\n * hard nofile 51200" >> /etc/security/limits.conf
fi

sysctl --system
. /etc/profile

mkdir -p /etc/shadowsocks

ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime


for svr in "apache2" "postfix" "systemd-resolved" "acpid" "exim4" "rpcbind.target"
do
    systemctl stop $svr
    systemctl disable $svr
done

cd $HOME
if [[ ! -e ${HOME}/.cargo/bin/cargo ]]
then
    curl https://sh.rustup.rs -sSf > $HOME/install_rust.sh
    sh $HOME/install_rust.sh -y
fi
cd $HOME
release_url=$(curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest"|grep download_url|grep stable|awk '{print $2}'|tr -d '"')
tarname="shadowsocks-rust.tar.xz"
wget -O ./$tarname "$release_url"
tar xvf $tarname 
mv ./ssserver /usr/local/bin/ssserver-rust
mv ./sslocal /usr/local/bin/sslocal-rust
mv ./ssurl /usr/local/bin/ssurl-rust
chown root:root /usr/local/bin/ssserver-rust
chown root:root /usr/local/bin/sslocal-rust
chown root:root /usr/local/bin/ssurl-rust

cd $HOME
if [[ ! -e /usr/local/bin/obfs-server ]]
then
    git clone https://github.com/shadowsocks/simple-obfs.git
    cd simple-obfs
    git submodule update --init --recursive
    ./autogen.sh
    ./configure && make
    make install
    cd $HOME
fi

echo -e "[Unit]\n\
Description=Shadowsocks Server Service\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=root\n\
ExecStart=/usr/local/bin/ssserver-rust -c /etc/shadowsocks/config.json\n\
Restart=always\n\
RestartSec=10\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n" > /lib/systemd/system/shadowsocks.service

selfip=`ip addr show | grep inet |grep -v 127.0.0 |grep -v inet6 |grep -v :: |awk '{print $2}'  |awk -F/ '{print $1}'`
echo -e "{\n \
    \"server\":\"$selfip\", \n \
    \"local_port\":1080, \n \
    \"local_address\":\"127.0.0.1\", \n \
    \"servers\": [\n \
        {
            \"server\":\"0.0.0.0\", \n \
            \"port\": 990, \n \
            \"password\": \"^Altale$\", \n \
            \"method\": \"aes-256-gcm\", \n \
            \"plugin\": \"obfs-server\", \n \
            \"plugin_opts\": \"obfs=tls\"
        }
    ], \n \
    \"timeout\": 300, \n \
    \"enable_udp\": true \n \
    }\n"  > /etc/shadowsocks/config.json

systemctl daemon-reload
systemctl enable shadowsocks
systemctl start shadowsocks
cd $HOME
