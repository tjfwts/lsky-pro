#!/bin/bash

# 检查是否以root用户运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以root权限运行" 1>&2
   exit 1
fi

# 安装必要依赖
if ! command -v docker &> /dev/null; then
    echo "未检测到Docker，正在安装Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker
    systemctl enable docker
fi

if ! command -v docker-compose &> /dev/null; then
    echo "未检测到docker-compose，正在安装..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

if ! command -v envsubst &> /dev/null; then
    echo "正在安装envsubst..."
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y gettext-base
    elif [ -f /etc/redhat-release ]; then
        yum install -y gettext
    else
        echo "无法自动安装envsubst，请手动安装后重新运行脚本"
        exit 1
    fi
fi

# 创建项目目录
PROJECT_DIR="/opt/lsky-pro"
echo "创建项目目录: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR" && cd "$PROJECT_DIR" || exit

# 步骤1：创建.env文件
echo "正在生成.env配置文件..."
cat > .env << EOF
# LSKY 环境配置
COMPOSE_PROJECT_NAME=lsky-prod

# MySQL 配置
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24)
MYSQL_DATABASE=lsky_data
MYSQL_USER=lsky_user
MYSQL_PASSWORD=$(openssl rand -base64 24)

# Lsky Pro 配置
WEB_PORT=8089
HOST_PORT=8001
EOF

# 显示生成的密码
echo -e "\n生成的数据库密码："
grep 'PASSWORD' .env

# 设置文件权限
chmod 600 .env

# 步骤2：创建docker-compose.yml
echo "正在创建docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  lskypro:
    image: halcyonazure/lsky-pro-docker:latest
    restart: unless-stopped
    hostname: lskypro
    container_name: lskypro
    environment:
      - WEB_PORT=${WEB_PORT}
    volumes:
      - ./web:/var/www/html/
    ports:
      - "${HOST_PORT}:${WEB_PORT}"
    networks:
      - lsky-net

  mysql-lsky:
    image: mysql:5.7.22
    restart: unless-stopped
    hostname: mysql-lsky
    container_name: mysql-lsky
    command: --default-authentication-plugin=mysql_native_password
    volumes:
      - ./mysql/data:/var/lib/mysql
      - ./mysql/conf:/etc/mysql
      - ./mysql/log:/var/log/mysql
      - ./mysql/init:/docker-entrypoint-initdb.d
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    networks:
      - lsky-net

networks:
  lsky-net:
EOF

# 步骤3：创建目录结构
echo "正在创建目录结构..."
mkdir -p web mysql/data mysql/conf mysql/log mysql/init backup

# 步骤5：创建MySQL初始化脚本
echo "正在生成MySQL权限脚本..."
cat > mysql/init/01-permissions.sql.template << 'EOF'
DROP USER IF EXISTS '${MYSQL_USER}'@'%';
CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${MYSQL_USER}'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TEMPORARY TABLES
ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF

# 加载环境变量
set -a
source .env
set +a

# 替换环境变量
envsubst < mysql/init/01-permissions.sql.template > mysql/init/01-permissions.sql
rm mysql/init/01-permissions.sql.template

# 步骤4：启动服务
echo "正在启动Docker服务..."
docker-compose up -d

# 等待服务启动
echo "等待服务初始化(约30秒)..."
sleep 30

# 获取本机IP地址
IP_ADDR=$(hostname -I | awk '{print $1}')
if [ -z "$IP_ADDR" ]; then
    IP_ADDR="localhost"
fi

# 显示安装结果
echo -e "\n\033[32m安装成功！\033[0m"
echo "====================================================="
echo "请通过以下地址完成安装:"
echo -e "\033[33mhttp://${IP_ADDR}:${HOST_PORT}\033[0m"
echo "====================================================="
echo "数据库配置信息:"
echo "主机: mysql-lsky"
echo "用户: ${MYSQL_USER}"
echo "密码: ${MYSQL_PASSWORD}"
echo "数据库: ${MYSQL_DATABASE}"
echo "====================================================="
echo "重要提示:"
echo "1. 首次访问请按上述地址完成网页安装"
echo "2. MySQL root密码可在 ${PROJECT_DIR}/.env 文件中查看"
echo "3. 所有数据存储在 ${PROJECT_DIR} 目录下"
echo "4. 备份目录: ${PROJECT_DIR}/backup"