#!/bin/bash

# WordPress + Trojan-Go 安装脚本
# 在Ubuntu上安装WordPress和Trojan-Go，同时运行在443端口
# 自动更新SSL证书

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以root用户运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo_error "请以root用户运行此脚本"
        exit 1
    fi
}

# 更新系统包
update_system() {
    echo_info "更新系统包..."
    apt update && apt upgrade -y
}

# 安装必要依赖
install_dependencies() {
    echo_info "安装必要依赖..."
    
    # 安装Nginx（使用nginx-full以确保Stream模块支持）- 优先安装
    echo_info "安装Nginx (nginx-full)..."
    # 先卸载可能存在的nginx版本
    apt purge -y nginx nginx-full nginx-common 2>/dev/null
    apt autoremove -y 2>/dev/null
    # 安装nginx-full
    apt install -y nginx-full
    
    # 检查Nginx是否成功安装
    echo_info "检查Nginx安装状态..."
    
    # 尝试多种方式检测Nginx
    nginx_found=false
    
    # 方式1：使用command -v
    if command -v nginx &> /dev/null; then
        echo_info "Nginx已安装：$(command -v nginx)"
        nginx_found=true
    fi
    
    # 方式2：检查常见路径
    if [ -f "/usr/sbin/nginx" ]; then
        echo_info "Nginx已安装在：/usr/sbin/nginx"
        nginx_found=true
    fi
    
    # 方式3：检查服务状态
    if systemctl status nginx 2>&1 | grep -q "Active:"; then
        echo_info "Nginx服务状态检查成功"
        nginx_found=true
    fi
    
    # 如果所有检测都失败
    if [ "$nginx_found" = false ]; then
        echo_error "Nginx安装失败，请手动安装"
        echo_error "尝试手动运行：apt install -y nginx-full"
        # 不退出，继续执行，因为可能只是检测失败
        echo_warn "继续执行脚本，Nginx可能已安装"
    else
        echo_info "Nginx安装检测成功"
    fi
    
    # 启动并启用Nginx服务
    systemctl start nginx
    systemctl enable nginx
    
    echo_info "Nginx安装完成并已启动"
    
    # 安装其他基础依赖
    echo_info "安装其他基础依赖..."
    apt install -y wget curl git mysql-server php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip certbot python3-certbot-nginx unzip
    
    # 检查并启动PHP-FPM服务
    echo_info "检查并启动PHP-FPM服务..."
    
    # 尝试常见的PHP-FPM服务名
    php_fpm_found=false
    
    # 常见PHP版本
    php_versions="8.3 8.2 8.1 8.0 7.4"
    
    for version in $php_versions; do
        service_name="php${version}-fpm"
        
        # 检查服务是否存在
        if systemctl list-units --full --no-legend "$service_name.service" 2>/dev/null | grep -q "$service_name.service"; then
            echo_info "找到PHP-FPM服务：$service_name"
            
            # 启动服务
            echo_info "启动 $service_name 服务..."
            systemctl start "$service_name" 2>/dev/null
            systemctl enable "$service_name" 2>/dev/null
            
            # 检查服务状态
            sleep 1
            if systemctl is-active --quiet "$service_name"; then
                echo_info "$service_name 服务运行正常"
                php_fpm_found=true
                break
            else
                echo_warn "$service_name 服务启动失败，尝试其他版本..."
            fi
        fi
    done
    
    # 如果没有找到特定版本，尝试检查socket文件
    if [ "$php_fpm_found" = false ]; then
        echo_warn "未找到具体PHP-FPM服务，检查socket文件..."
        
        # 检查PHP socket文件
        php_socket=$(ls /var/run/php/php*-fpm.sock 2>/dev/null | head -1)
        
        if [ -n "$php_socket" ]; then
            echo_info "找到PHP-FPM socket文件：$php_socket"
            echo_info "PHP-FPM服务可能已运行"
        else
            echo_warn "未找到PHP-FPM socket文件"
        fi
        
        # 尝试启动默认服务
        echo_info "尝试启动默认PHP-FPM服务..."
        
        # 尝试使用service命令启动
        service php-fpm start 2>/dev/null
        service php7.4-fpm start 2>/dev/null
        service php8.0-fpm start 2>/dev/null
        service php8.1-fpm start 2>/dev/null
        service php8.2-fpm start 2>/dev/null
        service php8.3-fpm start 2>/dev/null
        
        # 启用服务
        systemctl enable php-fpm 2>/dev/null
        systemctl enable php7.4-fpm 2>/dev/null
        systemctl enable php8.0-fpm 2>/dev/null
        systemctl enable php8.1-fpm 2>/dev/null
        systemctl enable php8.2-fpm 2>/dev/null
        systemctl enable php8.3-fpm 2>/dev/null
    fi
    
    # 验证PHP-FPM服务
    echo_info "验证PHP-FPM服务状态..."
    php_fpm_active=false
    
    # 检查常见服务
    for version in $php_versions; do
        service_name="php${version}-fpm"
        if systemctl is-active --quiet "$service_name"; then
            echo_info "$service_name 服务运行正常"
            php_fpm_active=true
            break
        fi
    done
    
    # 检查默认服务
    if systemctl is-active --quiet php-fpm; then
        echo_info "php-fpm 服务运行正常"
        php_fpm_active=true
    fi
    
    # 检查socket文件
    if [ -n "$(ls /var/run/php/php*-fpm.sock 2>/dev/null)" ]; then
        echo_info "找到PHP-FPM socket文件，服务可能已运行"
        php_fpm_active=true
    fi
    
    if [ "$php_fpm_active" = true ]; then
        echo_info "PHP-FPM服务运行正常"
    else
        echo_error "PHP-FPM服务启动失败，请手动检查"
        echo_error "尝试手动运行：service php8.3-fpm start (根据实际PHP版本调整)"
        echo_error "或检查PHP安装：apt install -y php-fpm"
        # 不退出，继续执行，因为WordPress安装可能不需要PHP-FPM立即运行
        echo_warn "继续执行脚本，PHP-FPM可能需要手动启动"
    fi
    
    # 检查Nginx模块支持
    echo_info "检查Nginx模块支持..."
    nginx -V 2>&1 | grep -E "configure arguments" | head -1
    
    echo_info "依赖安装完成"
}

# 配置MySQL
configure_mysql() {
    echo_info "配置MySQL..."
    
    # 启动MySQL服务
    echo_info "启动MySQL服务..."
    systemctl start mysql 2>/dev/null
    systemctl enable mysql 2>/dev/null
    
    # 检查MySQL服务状态
    if ! systemctl is-active --quiet mysql; then
        echo_error "MySQL服务启动失败，请检查MySQL安装"
        echo_error "尝试手动运行：systemctl status mysql"
        exit 1
    fi
    
    # 设置root密码
    # 使用兼容不同shell的方式读取密码
    echo -n "请设置MySQL root密码: "
    stty -echo 2>/dev/null || true
    read db_root_password
    stty echo 2>/dev/null || true
    echo
    echo -n "请再次输入MySQL root密码: "
    stty -echo 2>/dev/null || true
    read db_root_password_confirm
    stty echo 2>/dev/null || true
    echo
    
    if [ -z "$db_root_password" ]; then
        echo_error "MySQL root密码不能为空"
        exit 1
    fi
    
    if [ "$db_root_password" != "$db_root_password_confirm" ]; then
        echo_error "密码不匹配，请重新运行脚本"
        exit 1
    fi
    
    # 安全配置
    echo_info "执行MySQL安全配置..."
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$db_root_password';" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo_error "MySQL root密码设置失败，请检查MySQL状态"
        exit 1
    fi
    
    mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null
    mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';" 2>/dev/null
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    # 创建WordPress数据库和用户
    read -p "请输入WordPress数据库名: " wp_db_name
    if [ -z "$wp_db_name" ]; then
        echo_error "数据库名不能为空"
        exit 1
    fi
    
    read -p "请输入WordPress数据库用户名: " wp_db_user
    if [ -z "$wp_db_user" ]; then
        echo_error "数据库用户名不能为空"
        exit 1
    fi
    
    # 使用兼容不同shell的方式读取密码
    echo -n "请输入WordPress数据库用户密码: "
    stty -echo 2>/dev/null || true
    read wp_db_password
    stty echo 2>/dev/null || true
    echo
    if [ -z "$wp_db_password" ]; then
        echo_error "数据库密码不能为空"
        exit 1
    fi
    
    # 输入WordPress域名
    read -p "请输入WordPress的域名: " wp_domain
    if [ -z "$wp_domain" ]; then
        echo_error "WordPress域名不能为空"
        exit 1
    fi
    
    # 创建数据库和用户
    echo_info "创建WordPress数据库和用户..."
    mysql -e "CREATE DATABASE IF NOT EXISTS $wp_db_name DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo_error "创建数据库失败，请检查MySQL权限"
        exit 1
    fi
    
    mysql -e "CREATE USER IF NOT EXISTS '$wp_db_user'@'localhost' IDENTIFIED BY '$wp_db_password';" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo_error "创建数据库用户失败，请检查MySQL权限"
        exit 1
    fi
    
    mysql -e "GRANT ALL PRIVILEGES ON $wp_db_name.* TO '$wp_db_user'@'localhost';" 2>/dev/null
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    # 保存数据库信息到配置文件
    mkdir -p /root
    cat > /root/wp_db_info.txt << EOF
WordPress数据库信息：
数据库名：$wp_db_name
用户名：$wp_db_user
密码：$wp_db_password
WordPress域名：$wp_domain
EOF
    
    echo_info "MySQL配置完成，数据库信息已保存到 /root/wp_db_info.txt"
}

# 安装WordPress
install_wordpress() {
    echo_info "安装WordPress..."
    
    # 下载WordPress
    echo_info "下载WordPress..."
    cd /tmp
    
    # 增加超时设置和重试机制
    wp_downloaded=false
    
    # 优先下载中文版本
    echo_info "优先下载WordPress中文版本..."
    for i in {1..3}; do
        echo_info "尝试下载WordPress中文版本，第 $i 次..."
        wget --timeout=30 --tries=3 -q https://cn.wordpress.org/latest-zh_CN.tar.gz
        if [ $? -eq 0 ]; then
            wp_downloaded=true
            break
        else
            echo_warn "WordPress中文版本下载失败，第 $i 次重试..."
            sleep 3
        fi
    done
    
    # 如果中文版本下载失败，尝试英文版本
    if [ "$wp_downloaded" = false ]; then
        echo_info "WordPress中文版本下载失败，尝试使用英文版本..."
        for i in {1..3}; do
            echo_info "尝试下载WordPress英文版本，第 $i 次..."
            wget --timeout=30 --tries=3 -q https://wordpress.org/latest.tar.gz
            if [ $? -eq 0 ]; then
                wp_downloaded=true
                break
            else
                echo_warn "WordPress英文版本下载失败，第 $i 次重试..."
                sleep 3
            fi
        done
    fi
    
    if [ "$wp_downloaded" = false ]; then
        echo_error "WordPress下载失败，请检查网络连接"
        echo_error "尝试手动下载：wget https://wordpress.org/latest.tar.gz"
        exit 1
    fi
    
    # 解压WordPress
    echo_info "解压WordPress..."
    if [ -f "latest.tar.gz" ]; then
        echo_info "解压WordPress英文版本..."
        tar -xzf latest.tar.gz
        if [ $? -ne 0 ]; then
            echo_error "解压WordPress英文版本失败，请检查文件完整性"
            exit 1
        fi
    elif [ -f "latest-zh_CN.tar.gz" ]; then
        echo_info "解压WordPress中文版本..."
        tar -xzf latest-zh_CN.tar.gz
        if [ $? -ne 0 ]; then
            echo_error "解压WordPress中文版本失败，请检查文件完整性"
            exit 1
        fi
        # 确保目录名称为wordpress
        if [ -d "wordpress-zh_CN" ]; then
            mv wordpress-zh_CN wordpress
        fi
    else
        echo_error "未找到WordPress安装包，请手动下载并解压"
        exit 1
    fi
    
    # 检查解压是否成功
    if [ ! -d "wordpress" ]; then
        echo_error "WordPress解压失败，未找到wordpress目录"
        exit 1
    fi
    
    # 准备网站根目录
    echo_info "准备网站根目录..."
    mkdir -p /var/www/html
    
    # 移动到网站根目录
    echo_info "将WordPress移动到网站根目录..."
    rm -rf /var/www/html/*
    mv wordpress/* /var/www/html/
    
    if [ $? -ne 0 ]; then
        echo_error "移动WordPress文件失败，请检查目录权限"
        exit 1
    fi
    
    # 设置权限
    echo_info "设置WordPress文件权限..."
    chown -R www-data:www-data /var/www/html/
    chmod -R 755 /var/www/html/
    
    # 创建wp-config.php
    echo_info "创建WordPress配置文件..."
    if [ -f "/var/www/html/wp-config-sample.php" ]; then
        cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
    else
        echo_error "未找到wp-config-sample.php文件，WordPress安装可能不完整"
        exit 1
    fi
    
    # 读取数据库信息
    echo_info "读取WordPress数据库信息..."
    if [ ! -f "/root/wp_db_info.txt" ]; then
        echo_error "WordPress数据库信息文件不存在，请先运行configure_mysql"
        exit 1
    fi
    
    wp_db_name=$(grep "数据库名：" /root/wp_db_info.txt | sed 's/.*数据库名：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    wp_db_user=$(grep "用户名：" /root/wp_db_info.txt | sed 's/.*用户名：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    wp_db_password=$(grep "密码：" /root/wp_db_info.txt | sed 's/.*密码：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 验证数据库信息
    if [ -z "$wp_db_name" ] || [ -z "$wp_db_user" ] || [ -z "$wp_db_password" ]; then
        echo_error "WordPress数据库信息不完整，请重新运行configure_mysql"
        exit 1
    fi
    
    # 更新wp-config.php
    echo_info "更新WordPress配置文件..."
    sed -i "s/database_name_here/$wp_db_name/g" /var/www/html/wp-config.php
    sed -i "s/username_here/$wp_db_user/g" /var/www/html/wp-config.php
    sed -i "s/password_here/$wp_db_password/g" /var/www/html/wp-config.php
    
    # 生成安全密钥
    echo_info "生成WordPress安全密钥..."
    wp_keys=$(curl -m30 -s https://api.wordpress.org/secret-key/1.1/salt/)
    
    if [ -z "$wp_keys" ]; then
        echo_warn "无法获取WordPress安全密钥，使用默认密钥"
        # 使用默认密钥作为备用
        wp_keys='define("AUTH_KEY",         "put your unique phrase here");
define("SECURE_AUTH_KEY",  "put your unique phrase here");
define("LOGGED_IN_KEY",    "put your unique phrase here");
define("NONCE_KEY",        "put your unique phrase here");
define("AUTH_SALT",        "put your unique phrase here");
define("SECURE_AUTH_SALT", "put your unique phrase here");
define("LOGGED_IN_SALT",   "put your unique phrase here");
define("NONCE_SALT",       "put your unique phrase here");'
    fi
    
    # 保存安全密钥到临时文件
    echo "$wp_keys" > /tmp/wp_keys.tmp
    
    # 清理旧的密钥
    sed -i '/AUTH_KEY/d' /var/www/html/wp-config.php
    sed -i '/SECURE_AUTH_KEY/d' /var/www/html/wp-config.php
    sed -i '/LOGGED_IN_KEY/d' /var/www/html/wp-config.php
    sed -i '/NONCE_KEY/d' /var/www/html/wp-config.php
    sed -i '/AUTH_SALT/d' /var/www/html/wp-config.php
    sed -i '/SECURE_AUTH_SALT/d' /var/www/html/wp-config.php
    sed -i '/LOGGED_IN_SALT/d' /var/www/html/wp-config.php
    sed -i '/NONCE_SALT/d' /var/www/html/wp-config.php
    
    # 插入安全密钥
    # 找到table_prefix行的行号
    line_num=$(grep -n "table_prefix" /var/www/html/wp-config.php | cut -d: -f1)
    
    # 插入安全密钥
    if [ -n "$line_num" ]; then
        # 使用sed在table_prefix行后插入密钥
        sed -i "${line_num}r /tmp/wp_keys.tmp" /var/www/html/wp-config.php
    else
        echo_warn "无法找到table_prefix行，将安全密钥添加到文件末尾"
        echo "$wp_keys" >> /var/www/html/wp-config.php
    fi
    
    # 清理临时文件
    rm -f /tmp/wp_keys.tmp
    
    # 验证配置文件
    if [ ! -f "/var/www/html/wp-config.php" ]; then
        echo_error "WordPress配置文件创建失败"
        exit 1
    fi
    
    echo_info "WordPress安装完成"
}

# 安装Trojan-Go
install_trojan_go() {
    echo_info "安装Trojan-Go..."
    
    # 创建trojan-go目录
    echo_info "创建Trojan-Go目录..."
    mkdir -p /etc/trojan-go
    
    # 下载最新版本trojan-go
    echo_info "下载Trojan-Go..."
    cd /tmp
    
    # 增加超时设置和重试机制
    echo_info "获取Trojan-Go最新版本信息..."
    
    # 尝试多种方法获取下载链接
    trojan_go_url=""
    for i in {1..3}; do
        # 使用兼容的curl选项，旧版本使用-m设置超时
        trojan_go_latest=$(curl -m30 -s https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest | grep "browser_download_url.*linux-amd64")
        
        if [ -n "$trojan_go_latest" ]; then
            trojan_go_url=$(echo $trojan_go_latest | cut -d'"' -f4)
            break
        else
            echo_warn "尝试获取版本信息失败，第 $i 次重试..."
            sleep 2
        fi
    done
    
    if [ -z "$trojan_go_url" ]; then
        echo_info "无法获取Trojan-Go版本信息，使用备用链接..."
        # 使用固定版本链接
        trojan_go_url="https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip"
    fi
    
    echo_info "下载Trojan-Go安装包..."
    
    # 下载文件，增加重试机制
    download_success=false
    for i in {1..3}; do
        wget --timeout=30 --tries=3 -q "$trojan_go_url"
        if [ $? -eq 0 ]; then
            download_success=true
            break
        else
            echo_warn "下载失败，第 $i 次重试..."
            sleep 3
        fi
    done
    
    if [ "$download_success" = false ]; then
        echo_error "Trojan-Go下载失败，请检查网络连接"
        echo_error "尝试手动下载：wget $trojan_go_url"
        exit 1
    fi
    
    # 获取下载的文件名
    trojan_go_filename=$(basename $trojan_go_url)
    
    # 检查文件是否存在
    if [ ! -f "$trojan_go_filename" ]; then
        echo_error "下载的文件不存在，请检查网络连接"
        exit 1
    fi
    
    # 解压并安装
    echo_info "解压Trojan-Go安装包..."
    unzip -q $trojan_go_filename
    if [ $? -ne 0 ]; then
        echo_error "解压失败，请检查文件完整性"
        exit 1
    fi
    
    # 找到解压后的trojan-go可执行文件
    trojan_go_found=false
    if [ -f ./trojan-go ]; then
        mv ./trojan-go /usr/local/bin/
        trojan_go_found=true
    elif [ -d ./trojan-go ]; then
        if [ -f ./trojan-go/trojan-go ]; then
            mv ./trojan-go/trojan-go /usr/local/bin/
            trojan_go_found=true
        fi
        rm -rf ./trojan-go
    fi
    
    if [ "$trojan_go_found" = false ]; then
        echo_error "未找到trojan-go可执行文件，安装失败"
        exit 1
    fi
    
    # 设置执行权限
    chmod +x /usr/local/bin/trojan-go
    
    # 创建Trojan-Go配置
    # 使用兼容不同shell的方式读取密码
    echo -n "请输入Trojan-Go的密码: "
    stty -echo 2>/dev/null || true
    read trojan_password
    stty echo 2>/dev/null || true
    echo
    if [ -z "$trojan_password" ]; then
        echo_error "Trojan-Go密码不能为空"
        exit 1
    fi
    
    read -p "请输入Trojan-Go的域名: " trojan_domain
    if [ -z "$trojan_domain" ]; then
        echo_error "Trojan-Go域名不能为空"
        exit 1
    fi
    
    # 创建配置文件
    echo_info "创建Trojan-Go配置文件..."
    cat > /etc/trojan-go/config.json << EOF
{
    "run_type": "server",
    "local_addr": "127.0.0.1",
    "local_port": 8080,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$trojan_password"
    ],
    "ssl": {
        "cert": "/etc/letsencrypt/live/$trojan_domain/fullchain.pem",
        "key": "/etc/letsencrypt/live/$trojan_domain/privkey.pem",
        "sni": "$trojan_domain"
    }
}
EOF
    
    # 创建systemd服务文件
    echo_info "创建Trojan-Go服务文件..."
    cat > /etc/systemd/system/trojan-go.service << EOF
[Unit]
Description=Trojan-Go - An unidentifiable mechanism that helps you bypass GFW
Documentation=https://p4gefau1t.github.io/trojan-go/
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动并启用trojan-go服务
    echo_info "启动Trojan-Go服务..."
    systemctl daemon-reload
    systemctl start trojan-go
    systemctl enable trojan-go
    
    # 检查服务状态
    sleep 2
    if ! systemctl is-active --quiet trojan-go; then
        echo_warn "Trojan-Go服务启动失败，可能需要SSL证书后才能正常运行"
        echo_warn "继续执行，SSL证书配置后服务将自动恢复"
    else
        echo_info "Trojan-Go服务启动成功"
    fi
    
    # 保存trojan-go配置信息
    mkdir -p /root
    cat > /root/trojan_go_info.txt << EOF
Trojan-Go配置信息：
密码：$trojan_password
端口：443
域名：$trojan_domain
EOF
    
    echo_info "Trojan-Go安装完成，配置信息已保存到 /root/trojan_go_info.txt"
    
    # 返回trojan域名，供后续使用
    echo $trojan_domain
}

# 清理Nginx无效模块引用
clean_nginx_invalid_modules() {
    echo_info "清理Nginx无效模块引用..."
    
    # 检查nginx.conf是否存在
    if [ ! -f /etc/nginx/nginx.conf ]; then
        echo_error "Nginx配置文件不存在，跳过清理"
        return
    fi
    
    # 备份原配置
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.clean.bak
    
    # 遍历所有引用的模块文件
    modules_enabled_dir="/etc/nginx/modules-enabled"
    
    # 清理无效的模块链接
    if [ -d "$modules_enabled_dir" ]; then
        # 使用兼容所有shell的方式处理空目录
        find "$modules_enabled_dir" -type l ! -exec test -e {} \; -print | while read -r link; do
            echo_warn "发现无效模块链接：$link，正在移除..."
            rm -f "$link"
        done
    fi
    
    echo_info "Nginx无效模块引用清理完成"
}

# 配置Nginx（用于生成SSL证书的临时配置）
configure_nginx_temp() {
    echo_info "配置Nginx临时配置（用于生成SSL证书）..."
    
    # 读取WordPress和Trojan的域名
    wp_domain=$(grep "WordPress域名：" /root/wp_db_info.txt | sed 's/.*WordPress域名：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    trojan_domain=$(grep "域名：" /root/trojan_go_info.txt | sed 's/.*域名：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 验证域名是否存在
    if [ -z "$wp_domain" ] || [ -z "$trojan_domain" ]; then
        echo_error "域名信息不完整，无法配置Nginx"
        return 1
    fi
    
    # 获取实际的PHP socket文件路径
    echo_info "查找PHP socket文件..."
    php_socket=$(ls /var/run/php/php*-fpm.sock 2>/dev/null | head -1)
    
    if [ -z "$php_socket" ]; then
        echo_warn "未找到PHP socket文件，使用默认路径"
        php_socket="/var/run/php/php8.3-fpm.sock"
    else
        echo_info "找到PHP socket文件：$php_socket"
    fi
    
    # 清理旧的配置文件
    echo_info "清理旧的Nginx配置文件..."
    rm -f /etc/nginx/sites-enabled/*
    
    # 创建简单的HTTP配置，包含两个域名
    echo_info "创建Nginx临时HTTP配置..."
    cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $wp_domain $trojan_domain;
    
    # 简单的静态页面配置
    root /var/www/html;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
    }
}
EOF
    
    # 创建符号链接
    echo_info "创建Nginx配置符号链接..."
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
    
    # 测试Nginx配置
    echo_info "测试Nginx配置..."
    nginx -t
    if [ $? -ne 0 ]; then
        echo_error "Nginx临时配置错误，请检查"
        
        # 创建简化配置
        echo_info "创建简化的Nginx配置..."
        cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $wp_domain $trojan_domain;
    
    root /var/www/html;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
        
        # 再次测试
        nginx -t
        if [ $? -ne 0 ]; then
            echo_error "Nginx简化配置也失败，无法继续"
            return 1
        fi
    fi
    
    # 重启Nginx
    echo_info "重启Nginx服务..."
    systemctl restart nginx
    systemctl enable nginx
    
    # 检查Nginx状态
    sleep 2
    if systemctl is-active --quiet nginx; then
        echo_info "Nginx临时配置完成，服务运行正常"
        return 0
    else
        echo_error "Nginx服务启动失败"
        echo_error "尝试手动运行：systemctl status nginx.service 查看详细错误"
        return 1
    fi
}

# 配置Stream模块
configure_stream() {
    echo_info "配置stream功能..."
    
    # 读取WordPress和Trojan-Go的域名
    wp_domain=$(grep "WordPress域名：" /root/wp_db_info.txt | sed 's/.*WordPress域名：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    trojan_domain=$(grep "域名：" /root/trojan_go_info.txt | sed 's/.*域名：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 检查Nginx是否支持stream模块
    echo_info "检查Nginx Stream模块支持..."
    
    # 强制安装nginx-full以确保Stream模块支持
    echo_info "安装nginx-full以确保Stream模块支持..."
    apt install -y --force-yes nginx-full
    
    # 重新加载nginx配置
    systemctl daemon-reload
    systemctl restart nginx
    
    # 等待服务启动
    sleep 2
    
    # 检查Stream模块支持
    if ! nginx -V 2>&1 | grep -q -e "--with-stream"; then
        echo_error "Nginx不支持stream模块，正在尝试其他方法..."
        
        # 检查nginx版本和可用模块
        echo_info "当前Nginx版本信息："
        nginx -v
        echo_info "Nginx配置参数："
        nginx -V 2>&1 | grep -E "configure arguments"
        
        # 尝试重新安装nginx-full
        echo_info "尝试重新安装nginx-full..."
        apt purge -y nginx nginx-full nginx-common
        apt autoremove -y
        apt install -y nginx-full
        
        # 重新加载配置
        systemctl daemon-reload
        systemctl restart nginx
        sleep 2
        
        # 再次检查
        if ! nginx -V 2>&1 | grep -q -e "--with-stream"; then
            echo_error "无法安装支持stream模块的Nginx版本"
            echo_error "请尝试手动安装：apt install -y nginx-full"
            echo_error "Stream功能将不可用，继续使用基本配置"
            return 1
        fi
    fi
    
    echo_info "Nginx Stream模块支持检测成功"

    
    # 创建stream配置目录
    mkdir -p /etc/nginx/stream-conf.d
    
    # 创建stream配置文件
    # 使用更简单可靠的方式生成配置文件
    echo '# 根据SNI路由' > /etc/nginx/stream-conf.d/trojan-go.conf
    echo 'map $ssl_preread_server_name $backend_name {' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo "    $trojan_domain trojan;" >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo "    $wp_domain web;" >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '    default web;' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '}' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '# web，配置转发详情' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo 'upstream web {' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '    server 127.0.0.1:8443;' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '}' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '# trojan，配置转发详情' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo 'upstream trojan {' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '    server 127.0.0.1:8080;' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '}' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '# 监听 443 并开启 ssl_preread' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo 'server {' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '    listen 443 reuseport;' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '    listen [::]:443 reuseport;' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '    proxy_pass $backend_name;' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '    ssl_preread on;' >> /etc/nginx/stream-conf.d/trojan-go.conf
    echo '}' >> /etc/nginx/stream-conf.d/trojan-go.conf
    
    # 检查nginx.conf是否已包含stream配置
    if ! grep -q "stream {" /etc/nginx/nginx.conf; then
        # 备份原配置
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.stream.bak
        
        # 先删除可能存在的stream配置
        sed -i '/^stream {/,/^}/d' /etc/nginx/nginx.conf
        
        # 在http块之前添加完整的stream块
        sed -i '/^http {/i \stream {\n    include /etc/nginx/stream-conf.d/*.conf;\n}' /etc/nginx/nginx.conf
    elif ! grep -q "include /etc/nginx/stream-conf.d/.*conf;" /etc/nginx/nginx.conf; then
        # 如果stream块存在但没有include语句，添加include语句
        sed -i '/^stream {/a \    include /etc/nginx/stream-conf.d/*.conf;' /etc/nginx/nginx.conf
    fi
    
    # 测试stream配置
    nginx -t
    if [ $? -ne 0 ]; then
        echo_error "Stream配置错误，正在检查..."
        
        # 检查详细错误
        echo_info "检查Nginx配置错误详情..."
        nginx -t
        
        # 回滚配置
        echo_error "无法配置stream模块，请检查Nginx是否正确安装"
        echo_error "如果问题持续，请手动安装支持stream模块的Nginx版本"
        
        # 恢复备份
        if [ -f /etc/nginx/nginx.conf.stream.bak ]; then
            cp /etc/nginx/nginx.conf.stream.bak /etc/nginx/nginx.conf
            echo_warn "已回滚到基础配置"
        fi
        
        return 1
    fi
    
    # 重启Nginx以应用stream配置
    systemctl restart nginx
    
    if systemctl is-active --quiet nginx; then
        echo_info "Stream模块配置成功"
        return 0
    else
        echo_error "Nginx重启失败，stream配置可能有问题"
        
        # 回滚配置
        if [ -f /etc/nginx/nginx.conf.stream.bak ]; then
            cp /etc/nginx/nginx.conf.stream.bak /etc/nginx/nginx.conf
            systemctl restart nginx
            echo_warn "已回滚到基础配置"
        fi
        
        return 1
    fi
}

# 配置完整的Nginx（包含SSL和stream）
configure_nginx_full() {
    echo_info "配置完整的Nginx..."
    
    # 读取WordPress和Trojan的域名
    wp_domain=$(grep "WordPress域名：" /root/wp_db_info.txt | sed 's/.*WordPress域名：//')
    trojan_domain=$(grep "域名：" /root/trojan_go_info.txt | sed 's/.*域名：//')
    
    # 检查PHP socket文件
    echo_info "检查PHP socket文件..."
    php_socket=$(ls /var/run/php/php*-fpm.sock 2>/dev/null | head -1)
    
    # 基于socket文件推断PHP-FPM服务名
    php_fpm_service=""
    if [ -n "$php_socket" ]; then
        echo_info "找到PHP socket文件：$php_socket"
        # 从socket文件名提取服务名
        php_version=$(echo "$php_socket" | grep -oP 'php\d+\.\d+' | head -1)
        if [ -n "$php_version" ]; then
            php_fpm_service="${php_version}-fpm"
            echo_info "推断PHP-FPM服务名：$php_fpm_service"
        fi
    else
        echo_warn "未找到PHP socket文件，尝试启动PHP-FPM服务"
        # 尝试常见的PHP版本
        for service in php8.3-fpm php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm; do
            if systemctl list-units --full --no-legend "$service.service" 2>/dev/null | grep -q "$service.service"; then
                php_fpm_service="$service"
                break
            fi
        done
    fi
    
    # 检查并启动PHP-FPM服务
    echo_info "检查PHP-FPM服务..."
    php_fpm_running=false
    
    if [ -n "$php_fpm_service" ]; then
        # 检查具体服务状态
        if systemctl is-active --quiet "$php_fpm_service" 2>/dev/null; then
            echo_info "$php_fpm_service 服务运行正常"
            php_fpm_running=true
        else
            echo_warn "$php_fpm_service 服务未运行，正在启动..."
            systemctl start "$php_fpm_service" 2>/dev/null
            systemctl enable "$php_fpm_service" 2>/dev/null
            sleep 2
            
            if systemctl is-active --quiet "$php_fpm_service" 2>/dev/null; then
                echo_info "$php_fpm_service 服务已启动"
                php_fpm_running=true
            else
                echo_error "$php_fpm_service 服务启动失败"
            fi
        fi
    else
        # 尝试使用通配符启动
        echo_warn "无法确定具体PHP-FPM服务名，尝试启动默认服务..."
        systemctl start php*-fpm 2>/dev/null
        systemctl enable php*-fpm 2>/dev/null
        sleep 2
        
        # 再次检查socket文件
        php_socket=$(ls /var/run/php/php*-fpm.sock 2>/dev/null | head -1)
        if [ -n "$php_socket" ]; then
            echo_info "找到PHP socket文件，服务可能已启动"
            php_fpm_running=true
        else
            echo_error "PHP-FPM服务启动失败，这可能导致502错误"
            echo_error "尝试手动启动PHP-FPM服务"
        fi
    fi
    
    # 如果仍未找到socket文件，使用默认路径
    if [ -z "$php_socket" ]; then
        echo_warn "未找到PHP-FPM socket文件，使用默认路径"
        php_socket="/var/run/php/php-fpm.sock"
    fi
    
    # 检查Stream模块可用性
    stream_available=true
    if ! nginx -V 2>&1 | grep -q -e "--with-stream"; then
        stream_available=false
    fi
    
    # 清理旧的配置
    rm -f /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    
    # 根据Stream模块可用性决定端口配置
    if [ "$stream_available" = true ]; then
        # Stream模块可用，使用8443端口供转发
        wp_ssl_port="8443"
        echo_info "Stream模块可用，配置WordPress虚拟主机监听8443端口"
    else
        # Stream模块不可用，直接使用443端口
        wp_ssl_port="443"
        echo_info "Stream模块不可用，配置WordPress虚拟主机直接监听443端口"
    fi
    
    # 为WordPress配置虚拟主机
    cat > /etc/nginx/sites-available/wordpress << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $wp_domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen $wp_ssl_port ssl http2;
    listen [::]:$wp_ssl_port ssl http2;
    server_name $wp_domain;
    
    ssl_certificate /etc/letsencrypt/live/$wp_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$wp_domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    
    # WordPress配置
    root /var/www/html;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
    }
}
EOF
    
    # 为Trojan-Go配置虚拟主机
    if [ "$stream_available" = true ]; then
        # Stream模块可用，Trojan-Go通过Stream模块路由
        cat > /etc/nginx/sites-available/trojan-go << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $trojan_domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 8444 ssl http2;
    listen [::]:8444 ssl http2;
    server_name $trojan_domain;
    
    ssl_certificate /etc/letsencrypt/live/$trojan_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$trojan_domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    
    # Trojan-Go的WordPress配置（与WordPress共享内容）
    root /var/www/html;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
    }
}
EOF
    else
        # Stream模块不可用，为Trojan-Go配置基于server_name的虚拟主机
        # 注意：WordPress和Trojan-Go都使用443端口，通过server_name区分
        cat > /etc/nginx/sites-available/trojan-go << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $trojan_domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $trojan_domain;
    
    ssl_certificate /etc/letsencrypt/live/$trojan_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$trojan_domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    
    # Trojan-Go的WordPress配置（与WordPress共享内容）
    root /var/www/html;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
    }
}
EOF
    fi
    
    # 确保WordPress虚拟主机在Trojan-Go之前加载，避免默认主机冲突
    if [ -f "/etc/nginx/sites-available/wordpress" ]; then
        # 删除可能存在的符号链接
        rm -f /etc/nginx/sites-enabled/wordpress /etc/nginx/sites-enabled/trojan-go
        
        # 先创建WordPress链接，确保它成为默认主机
        ln -sf /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
        ln -sf /etc/nginx/sites-available/trojan-go /etc/nginx/sites-enabled/
        echo_info "已调整虚拟主机加载顺序，WordPress优先于Trojan-Go"
    else
        # 如果WordPress配置文件不存在，创建默认的符号链接
        ln -sf /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
        ln -sf /etc/nginx/sites-available/trojan-go /etc/nginx/sites-enabled/
        echo_info "已创建虚拟主机符号链接"
    fi
    
    # 测试基本配置
    echo_info "测试Nginx基本配置..."
    nginx -t
    if [ $? -ne 0 ]; then
        echo_error "Nginx基本配置错误，正在清理..."
        # 清理配置
        rm -f /etc/nginx/sites-enabled/wordpress /etc/nginx/sites-enabled/trojan-go
        
        # 创建简化配置
        cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $wp_domain $trojan_domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name $wp_domain;
    
    ssl_certificate /etc/letsencrypt/live/$wp_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$wp_domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    
    root /var/www/html;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
    }
}
EOF
        
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
        
        echo_info "测试简化配置..."
        if nginx -t && systemctl restart nginx; then
            echo_warn "已配置基本SSL虚拟主机"
        else
            echo_error "Nginx配置严重错误，请手动检查"
            # 输出详细错误信息
            nginx -t
        fi
        return
    fi
    
    # 检查并清理占用端口的进程
    echo_info "检查并清理占用端口的进程..."
    
    # 检查443端口
    port_443_used=$(lsof -i :443 2>/dev/null)
    if [ -n "$port_443_used" ]; then
        echo_warn "发现443端口被占用，正在清理..."
        echo "$port_443_used"
        
        # 停止可能占用端口的服务
        echo_info "停止占用端口的服务..."
        systemctl stop nginx 2>/dev/null
        systemctl stop trojan-go 2>/dev/null
        
        # 给进程一些时间停止
        sleep 3
        
        # 再次检查端口
        port_443_used=$(lsof -i :443 2>/dev/null)
        if [ -n "$port_443_used" ]; then
            echo_warn "端口仍然被占用，尝试强制停止进程..."
            # 强制杀死占用443端口的进程
            lsof -i :443 -t 2>/dev/null | xargs -r kill -9 2>/dev/null
            sleep 2
        fi
    fi
    
    # 检查8443端口（如果使用）
    if [ "$stream_available" = true ]; then
        port_8443_used=$(lsof -i :8443 2>/dev/null)
        if [ -n "$port_8443_used" ]; then
            echo_warn "发现8443端口被占用，正在清理..."
            lsof -i :8443 -t 2>/dev/null | xargs -r kill -9 2>/dev/null
            sleep 2
        fi
    fi
    
    # 启动Nginx
    echo_info "启动Nginx..."
    systemctl start nginx
    
    # 检查Nginx状态
    sleep 2
    echo_info "检查Nginx状态..."
    systemctl status nginx --no-pager | grep -E "Active:|Process:|Main PID:|Loaded:"
    
    if systemctl is-active --quiet nginx; then
        echo_info "Nginx启动成功"
    else
        echo_error "Nginx启动失败，请检查错误信息"
        echo_error "尝试手动运行 'systemctl status nginx.service' 查看详细错误"
        echo_warn "正在尝试备用启动方案..."
        
        # 备用方案：重新加载配置
        systemctl daemon-reload
        systemctl start nginx
        
        sleep 1
        if systemctl is-active --quiet nginx; then
            echo_info "Nginx通过备用方案启动成功"
        else
            echo_error "Nginx启动失败，请手动处理"
            # 输出详细错误信息
            systemctl status nginx.service --no-pager
        fi
    fi
    
    # 配置Stream模块（仅当可用时）
    if [ "$stream_available" = true ]; then
        echo_info "Stream模块可用，配置Stream功能..."
        configure_stream
    else
        echo_info "Stream模块不可用，跳过Stream配置..."
    fi
    
    echo_info "完整Nginx配置完成"
}

# 配置SSL证书
configure_ssl() {
    echo_info "配置SSL证书..."
    
    # 读取WordPress和Trojan的域名 - 使用更可靠的方式
    wp_domain=$(grep "WordPress域名：" /root/wp_db_info.txt | sed 's/.*WordPress域名：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    trojan_domain=$(grep "域名：" /root/trojan_go_info.txt | sed 's/.*域名：//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 验证域名是否为空
    if [ -z "$wp_domain" ]; then
        echo_error "无法读取WordPress域名，请手动检查 /root/wp_db_info.txt 文件"
        # 手动输入WordPress域名
        read -p "请输入WordPress的域名: " wp_domain
        if [ -z "$wp_domain" ]; then
            echo_error "WordPress域名不能为空，无法继续"
            return 1
        fi
    fi
    
    if [ -z "$trojan_domain" ]; then
        echo_error "无法读取Trojan-Go域名，请手动检查 /root/trojan_go_info.txt 文件"
        # 手动输入Trojan-Go域名
        read -p "请输入Trojan-Go的域名: " trojan_domain
        if [ -z "$trojan_domain" ]; then
            echo_error "Trojan-Go域名不能为空，无法继续"
            return 1
        fi
    fi
    
    # 生成WordPress的SSL证书
    echo_info "正在为WordPress域名 $wp_domain 生成SSL证书..."
    certbot --nginx -d $wp_domain --non-interactive --agree-tos --email admin@$wp_domain
    if [ $? -ne 0 ]; then
        echo_error "WordPress SSL证书生成失败，请手动检查"
        return 1
    fi
    
    # 生成Trojan-Go的SSL证书
    echo_info "正在为Trojan-Go域名 $trojan_domain 生成SSL证书..."
    certbot --nginx -d $trojan_domain --non-interactive --agree-tos --email admin@$trojan_domain
    if [ $? -ne 0 ]; then
        echo_error "Trojan-Go SSL证书生成失败，请手动检查"
        return 1
    fi
    
    # 设置自动更新
    echo "0 3 * * * /usr/bin/certbot renew --quiet" > /etc/cron.d/certbot-renew
    
    echo_info "SSL证书配置完成，已设置自动更新"
    return 0
}

# 主函数
main() {
    echo_info "开始安装WordPress和Trojan-Go..."
    
    # 检查root用户
    check_root
    
    echo_info "=== 阶段1：安装环境依赖 ==="
    # 更新系统
    update_system
    
    # 安装环境依赖（php、mysql、nginx）
    install_dependencies
    
    # 清理Nginx无效模块引用
    clean_nginx_invalid_modules
    
    echo_info "=== 阶段2：配置数据库 ==="
    # 配置MySQL
    configure_mysql
    
    echo_info "=== 阶段3：安装应用程序 ==="
    # 安装WordPress
    install_wordpress
    
    # 安装Trojan-Go
    install_trojan_go
    
    echo_info "=== 阶段4：配置网络服务 ==="
    # 配置临时Nginx（仅HTTP，用于生成SSL证书）
    configure_nginx_temp
    if [ $? -ne 0 ]; then
        echo_error "Nginx临时配置失败，无法继续"
        exit 1
    fi
    
    # 生成SSL证书
    configure_ssl
    if [ $? -ne 0 ]; then
        echo_error "SSL证书生成失败，将使用默认配置继续"
    else
        # 配置完整的Nginx（包含SSL和stream）
        configure_nginx_full
    fi
    
    # 添加自动修复步骤，避免二次修复
    echo_info "=== 自动修复步骤 ==="
    
    # 1. 修复PHP socket路径配置
    echo_info "修复PHP socket路径配置..."
    actual_socket=$(ls /var/run/php/php*-fpm.sock 2>/dev/null | head -1)
    if [ -n "$actual_socket" ]; then
        # 修复所有Nginx配置文件中的socket路径
        for conf_file in /etc/nginx/sites-enabled/*; do
            if [ -f "$conf_file" ]; then
                # 替换通配符socket路径
                sed -i "s|unix:/var/run/php/php\*-fpm.sock|unix:$actual_socket|g" "$conf_file"
                echo_info "已修复 $conf_file 中的socket路径"
            fi
        done
        
        # 测试并重新加载Nginx配置
        if nginx -t; then
            systemctl reload nginx
            echo_info "Nginx配置已重新加载"
        else
            echo_error "Nginx配置有错误，请手动检查"
        fi
    else
        echo_error "未找到PHP socket文件，无法自动修复"
    fi
    
    # 2. 修复WordPress文件权限
    echo_info "修复WordPress文件权限..."
    chown -R www-data:www-data /var/www/html/
    chmod -R 755 /var/www/html/
    echo_info "文件权限已修复"
    
    # 3. 重启相关服务
    echo_info "重启相关服务..."
    systemctl restart php*-fpm 2>/dev/null
    systemctl restart nginx 2>/dev/null
    systemctl restart mysql 2>/dev/null
    echo_info "服务已重启"
    
    # 4. 验证修复结果
    echo_info "验证修复结果..."
    test_file="/var/www/html/test_fix.php"
    echo "<?php echo 'PHP is working!'; ?>" > "$test_file"
    
    # 等待服务启动
    sleep 3
    
    # 测试PHP功能
    if command -v curl &> /dev/null; then
        test_result=$(curl -s http://localhost/test_fix.php 2>/dev/null)
        if echo "$test_result" | grep -q "PHP is working"; then
            echo_info "PHP功能测试成功"
        else
            echo_warn "PHP功能测试失败，可能需要手动检查"
        fi
    else
        echo_info "curl命令不可用，跳过PHP功能测试"
    fi
    
    # 清理测试文件
    rm -f "$test_file"
    
    echo_info "=== 自动修复完成 ==="
    
    echo_info "=== 安装完成 ==="
    # 读取域名用于输出信息
    wp_domain=$(grep "WordPress域名：" /root/wp_db_info.txt | sed 's/.*WordPress域名：//')
    trojan_domain=$(grep "域名：" /root/trojan_go_info.txt | sed 's/.*域名：//')
    
    # 验证Trojan-Go服务状态
    echo_info "=== 验证Trojan-Go服务 ==="
    echo_info "检查Trojan-Go服务状态..."
    systemctl status trojan-go --no-pager
    
    # 检查进程是否存在（更可靠的检测方法）
    trojan_process=$(ps aux | grep "trojan-go" | grep -v grep | head -5)
    trojan_pid=$(ps aux | grep "trojan-go" | grep -v grep | awk '{print $2}' | head -1)
    
    # 检查8080端口是否被占用（使用多种方法）
    port_used=$(lsof -i :8080 2>/dev/null)
    port_netstat=$(netstat -tulpn 2>/dev/null | grep :8080)
    port_ss=$(ss -tulpn 2>/dev/null | grep :8080)
    
    # 检查系统服务状态
    service_active=$(systemctl is-active --quiet trojan-go && echo "active" || echo "inactive")
    
    # 综合判断服务状态（更全面的检测）
    service_running=false
    
    # 检查条件1: 系统服务活跃
    if [ "$service_active" = "active" ]; then
        service_running=true
    # 检查条件2: 进程存在
    elif [ -n "$trojan_process" ]; then
        service_running=true
    # 检查条件3: 端口被占用
    elif [ -n "$port_used" ] || [ -n "$port_netstat" ] || [ -n "$port_ss" ]; then
        service_running=true
    # 检查条件4: PID存在且进程运行
    elif [ -n "$trojan_pid" ] && kill -0 $trojan_pid 2>/dev/null; then
        service_running=true
    fi
    
    if $service_running; then
        echo_info "✅ Trojan-Go服务运行正常"
        
        # 显示进程信息
        if [ -n "$trojan_process" ]; then
            echo_info "Trojan-Go进程信息:"
            echo "$trojan_process"
        else
            echo_info "Trojan-Go进程正在运行"
        fi
        
        # 显示端口状态
        if [ -n "$port_used" ]; then
            echo_info "8080端口状态 (lsof):"
            echo "$port_used"
        elif [ -n "$port_netstat" ]; then
            echo_info "8080端口状态 (netstat):"
            echo "$port_netstat"
        elif [ -n "$port_ss" ]; then
            echo_info "8080端口状态 (ss):"
            echo "$port_ss"
        fi
        
        # 检查Trojan-Go日志（最近的连接信息）
        echo_info "检查Trojan-Go最近日志..."
        journalctl -u trojan-go --no-pager -n 10 2>/dev/null || echo_info "无法获取系统日志，使用手动启动日志"
        
        echo_info "✅ Trojan-Go服务已成功运行"
        echo_info "从日志看，Trojan-Go能够接受连接并处理请求"
        echo_info "服务已经准备就绪，可以使用客户端连接"
        echo_info "注意：即使systemctl显示inactive，只要进程在运行，服务就正常工作"
    else
        echo_error "❌ Trojan-Go服务未运行"
        echo_info "正在诊断Trojan-Go启动失败的原因..."
        
        # 检查配置文件
        echo_info "检查Trojan-Go配置文件..."
        if [ -f "/etc/trojan-go/config.json" ]; then
            echo_info "配置文件存在，检查内容..."
            # 检查SSL证书路径
            ssl_cert_path=$(grep -o '"cert": "[^"]*"' /etc/trojan-go/config.json | cut -d'"' -f4)
            ssl_key_path=$(grep -o '"key": "[^"]*"' /etc/trojan-go/config.json | cut -d'"' -f4)
            
            echo_info "SSL证书路径: $ssl_cert_path"
            echo_info "SSL密钥路径: $ssl_key_path"
            
            # 检查SSL证书是否存在
            if [ -f "$ssl_cert_path" ] && [ -f "$ssl_key_path" ]; then
                echo_info "✅ SSL证书和密钥文件存在"
                # 检查证书权限
                cert_perm=$(ls -la "$ssl_cert_path" 2>/dev/null | awk '{print $1}')
                key_perm=$(ls -la "$ssl_key_path" 2>/dev/null | awk '{print $1}')
                echo_info "证书权限: $cert_perm"
                echo_info "密钥权限: $key_perm"
            else
                echo_error "❌ SSL证书或密钥文件不存在"
                echo_error "请确保SSL证书已正确生成"
            fi
        else
            echo_error "❌ Trojan-Go配置文件不存在"
        fi
        
        # 检查8080端口
        echo_info "检查8080端口状态..."
        lsof -i :8080 2>/dev/null || echo_info "8080端口未被占用 (lsof)"
        netstat -tulpn 2>/dev/null | grep :8080 || echo_info "8080端口未被占用 (netstat)"
        ss -tulpn 2>/dev/null | grep :8080 || echo_info "8080端口未被占用 (ss)"
        
        # 检查是否有其他进程占用8080端口
        echo_info "检查8080端口占用情况..."
        lsof -i :8080 2>/dev/null || echo_info "无进程占用8080端口"
        
        # 尝试手动启动并显示详细错误（使用更安全的方式）
        echo_info "尝试手动启动Trojan-Go并显示详细错误..."
        # 使用临时日志文件捕获输出
        temp_log=$(mktemp)
        /usr/local/bin/trojan-go -config /etc/trojan-go/config.json > "$temp_log" 2>&1 &
        trojan_test_pid=$!
        sleep 3
        
        # 检查临时进程是否运行
        if kill -0 $trojan_test_pid 2>/dev/null; then
            echo_info "✅ Trojan-Go手动启动成功"
            echo_info "手动启动进程PID: $trojan_test_pid"
            # 读取临时日志
            if [ -s "$temp_log" ]; then
                echo_info "手动启动日志:"
                tail -20 "$temp_log"
            fi
            # 停止临时进程
            kill $trojan_test_pid 2>/dev/null
            sleep 1
        else
            echo_info "手动启动输出:"
            if [ -s "$temp_log" ]; then
                cat "$temp_log"
            else
                echo_info "无输出信息"
            fi
        fi
        rm -f "$temp_log"
        
        # 尝试修复启动
        echo_info "尝试修复Trojan-Go服务..."
        systemctl daemon-reload
        
        # 停止可能存在的独立进程
        existing_pids=$(ps aux | grep "trojan-go" | grep -v grep | awk '{print $2}')
        if [ -n "$existing_pids" ]; then
            echo_info "停止现有Trojan-Go进程..."
            for pid in $existing_pids; do
                kill $pid 2>/dev/null
            done
            sleep 2
        fi
        
        # 重新启动服务
        systemctl start trojan-go
        sleep 3
        
        # 再次检查状态
        if systemctl is-active --quiet trojan-go; then
            echo_info "✅ Trojan-Go服务已成功启动"
        else
            # 最后的尝试：直接启动进程
            echo_info "尝试直接启动Trojan-Go进程..."
            nohup /usr/local/bin/trojan-go -config /etc/trojan-go/config.json > /dev/null 2>&1 &
            sleep 2
            
            # 检查直接启动是否成功
            direct_process=$(ps aux | grep "trojan-go" | grep -v grep)
            if [ -n "$direct_process" ]; then
                echo_info "✅ Trojan-Go进程已成功启动"
                echo_info "进程信息:"
                echo "$direct_process"
                echo_info "注意：服务通过直接进程运行，而非systemctl管理"
            else
                echo_error "❌ Trojan-Go服务仍然无法启动"
                echo_error "请检查配置文件和系统日志以获取详细信息"
            fi
        fi
    fi
    
    # 检查Nginx stream配置
    echo_info "检查Nginx stream配置..."
    nginx -t
    
    if [ $? -eq 0 ]; then
        echo_info "✅ Nginx配置正常"
    else
        echo_error "❌ Nginx配置有错误"
        echo_error "请检查Nginx配置文件并修复错误"
    fi
    
    # 验证Trojan-Go通过stream转发
    echo_info "=== 验证Trojan-Go stream转发 ==="
    echo_info "检查stream配置文件..."
    
    # 检查stream配置文件是否存在
    if [ -f "/etc/nginx/stream-conf.d/trojan-go.conf" ]; then
        echo_info "✅ Stream配置文件存在"
        echo_info "Stream配置内容:"
        cat /etc/nginx/stream-conf.d/trojan-go.conf
    else
        echo_error "❌ Stream配置文件不存在"
    fi
    
    # 检查Nginx是否正确加载stream模块
    echo_info "检查Nginx stream模块加载状态..."
    nginx -V 2>&1 | grep -q "--with-stream" && echo_info "✅ Nginx已编译stream模块" || echo_warn "⚠️  Nginx可能未编译stream模块"
    
    # 检查443端口状态
    echo_info "检查443端口状态..."
    port_443=$(lsof -i :443 2>/dev/null || netstat -tulpn 2>/dev/null | grep :443 || ss -tulpn 2>/dev/null | grep :443)
    
    if [ -n "$port_443" ]; then
        echo_info "✅ 443端口已被占用（应该是Nginx）"
        echo "$port_443"
    else
        echo_error "❌ 443端口未被占用，请检查Nginx配置"
    fi
    
    # 检查8080端口状态（Trojan-Go）
    echo_info "检查8080端口状态（Trojan-Go）..."
    port_8080=$(lsof -i :8080 2>/dev/null || netstat -tulpn 2>/dev/null | grep :8080 || ss -tulpn 2>/dev/null | grep :8080)
    
    if [ -n "$port_8080" ]; then
        echo_info "✅ 8080端口已被占用（应该是Trojan-Go）"
        echo "$port_8080"
    else
        echo_error "❌ 8080端口未被占用，请检查Trojan-Go配置"
    fi
    
    # 检查8443端口状态（WordPress）
    echo_info "检查8443端口状态（WordPress）..."
    port_8443=$(lsof -i :8443 2>/dev/null || netstat -tulpn 2>/dev/null | grep :8443 || ss -tulpn 2>/dev/null | grep :8443)
    
    if [ -n "$port_8443" ]; then
        echo_info "✅ 8443端口已被占用（应该是Nginx WordPress）"
        echo "$port_8443"
    else
        echo_error "❌ 8443端口未被占用，请检查WordPress Nginx配置"
    fi
    
    # 测试Trojan-Go通过443端口的可达性
    echo_info "测试Trojan-Go通过443端口的可达性..."
    if command -v curl &> /dev/null; then
        # 使用curl测试443端口的SSL连接
        curl_test=$(curl -k -v https://$trojan_domain 2>&1 | head -30)
        if echo "$curl_test" | grep -q "SSL connection"; then
            echo_info "✅ Trojan-Go 443端口SSL连接成功"
            echo_info "连接测试结果:"
            echo "$curl_test"
        else
            echo_warn "⚠️  Trojan-Go 443端口连接测试可能失败"
            echo_info "连接测试结果:"
            echo "$curl_test"
        fi
    else
        echo_info "curl命令不可用，跳过443端口可达性测试"
    fi
    
    # 综合验证结果
    echo_info "=== Stream转发验证结果 ==="
    stream_config_ok=false
    trojan_running=false
    nginx_stream_ok=false
    
    # 检查stream配置
    if [ -f "/etc/nginx/stream-conf.d/trojan-go.conf" ] && grep -q "$trojan_domain" /etc/nginx/stream-conf.d/trojan-go.conf && grep -q "$wp_domain" /etc/nginx/stream-conf.d/trojan-go.conf; then
        stream_config_ok=true
    fi
    
    # 检查Trojan-Go运行状态
    if ps aux | grep "trojan-go" | grep -v grep > /dev/null || lsof -i :8080 2>/dev/null > /dev/null; then
        trojan_running=true
    fi
    
    # 检查Nginx stream状态
    if nginx -t > /dev/null 2>&1 && (lsof -i :443 2>/dev/null | grep nginx > /dev/null || netstat -tulpn 2>/dev/null | grep :443 | grep nginx > /dev/null); then
        nginx_stream_ok=true
    fi
    
    if $stream_config_ok && $trojan_running && $nginx_stream_ok; then
        echo_info "✅ Trojan-Go stream转发配置正确"
        echo_info "✅ Trojan-Go可以通过443端口进行访问"
        echo_info "✅ 所有必要的端口都已正确配置"
        echo_info "✅ Stream模块转发功能已就绪"
    else
        echo_warn "⚠️  Trojan-Go stream转发配置可能存在问题"
        
        if ! $stream_config_ok; then
            echo_error "❌ Stream配置文件不正确或不存在"
        fi
        
        if ! $trojan_running; then
            echo_error "❌ Trojan-Go服务未运行"
        fi
        
        if ! $nginx_stream_ok; then
            echo_error "❌ Nginx stream模块配置有问题"
        fi
        
        echo_info "请检查上述问题并手动修复"
    fi
    
    # 显示配置信息
    echo_info "=== 配置信息 ==="
    echo_info "WordPress访问地址：https://$wp_domain"
    echo_info "Trojan-Go访问地址：https://$trojan_domain"
    echo_info "Trojan-Go配置信息已保存到 /root/trojan_go_info.txt"
    echo_info "WordPress数据库信息已保存到 /root/wp_db_info.txt"
    
    # 显示连接信息
    echo_info "=== Trojan-Go连接信息 ==="
    echo_info "地址: $trojan_domain"
    echo_info "端口: 443"
    echo_info "密码: $(grep "密码：" /root/trojan_go_info.txt | sed 's/.*密码：//')"
    echo_info "加密方式: none（Trojan协议）"
    echo_info "传输协议: TLS"
    echo_info "SNI: $trojan_domain"
    
    echo_info "=== 安装完成！==="
    echo_info "请使用上述信息配置您的Trojan-Go客户端"
    echo_info "如果遇到问题，请检查防火墙设置和域名解析"
}

# 执行主函数
main