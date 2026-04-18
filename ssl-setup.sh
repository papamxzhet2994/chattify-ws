#!/bin/bash

echo "🔒 Настройка SSL для WebSocket сервера..."
echo "========================================"

# Проверяем, установлен ли certbot
if ! command -v certbot &> /dev/null; then
    echo "📦 Устанавливаем certbot..."
    apt update
    apt install -y certbot python3-certbot-nginx
else
    echo "✅ Certbot уже установлен"
fi

# Проверяем, что nginx работает
echo "🌐 Проверяем статус nginx..."
systemctl status nginx --no-pager -l

# Проверяем, что домен доступен
echo "🔍 Проверяем DNS для ws.chattify.site..."
nslookup ws.chattify.site

echo ""
echo "⚠️  ВАЖНО: Убедитесь, что:"
echo "1. DNS для ws.chattify.site настроен на IP этого сервера"
echo "2. Порт 80 открыт в firewall"
echo "3. nginx работает и доступен по адресу ws.chattify.site"
echo ""

read -p "Продолжить настройку SSL? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Настройка SSL отменена"
    exit 1
fi

# Получаем SSL сертификат
echo "🔒 Получаем SSL сертификат для ws.chattify.site..."
certbot --nginx -d ws.chattify.site --non-interactive --agree-tos --email admin@chattify.site

# Проверяем результат
if [ $? -eq 0 ]; then
    echo "✅ SSL сертификат успешно получен!"
    
    # Обновляем конфигурацию nginx для WebSocket с SSL
    echo "🌐 Обновляем конфигурацию nginx..."
    cat > /etc/nginx/sites-available/websocket-server << 'NGINX_SSL_EOF'
server {
    listen 80;
    server_name ws.chattify.site;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ws.chattify.site;

    ssl_certificate /etc/letsencrypt/live/ws.chattify.site/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ws.chattify.site/privkey.pem;
    
    # SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Увеличиваем таймауты для WebSocket
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    # Настройки для WebSocket
    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_cache_bypass $http_upgrade;
        
        # Дополнительные заголовки для WebSocket
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $host;
        
        # Отключаем буферизацию для real-time
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # Специальная обработка для Socket.IO
    location /socket.io/ {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_cache_bypass $http_upgrade;
        
        # Дополнительные заголовки для Socket.IO
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $host;
        
        # Отключаем буферизацию
        proxy_buffering off;
        proxy_request_buffering off;
        
        # Увеличиваем таймауты для long polling
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check endpoint
    location /health {
        proxy_pass http://localhost:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
NGINX_SSL_EOF

    # Проверяем конфигурацию nginx
    echo "🔍 Проверяем конфигурацию nginx..."
    nginx -t

    # Перезапускаем nginx
    echo "🔄 Перезапускаем nginx..."
    systemctl restart nginx

    # Настраиваем автопродление сертификата
    echo "🔄 Настраиваем автопродление сертификата..."
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

    echo "✅ SSL настройка завершена!"
    echo ""
    echo "🔍 Проверьте работу:"
    echo "- HTTPS: https://ws.chattify.site/health"
    echo "- WebSocket: wss://ws.chattify.site"
    echo ""
    echo "📋 Обновите настройки в приложениях:"
    echo "- Laravel: REACT_APP_WEBSOCKET_URL=wss://ws.chattify.site"
    echo "- React: REACT_APP_WEBSOCKET_URL=wss://ws.chattify.site"
    
else
    echo "❌ Ошибка при получении SSL сертификата"
    echo "Проверьте:"
    echo "1. DNS настройки для ws.chattify.site"
    echo "2. Доступность порта 80"
    echo "3. Логи certbot: certbot logs"
fi 