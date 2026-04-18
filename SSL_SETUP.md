# Настройка SSL для WebSocket сервера

## Проблема
Firefox не может установить соединение с `wss://ws.chattify.site` потому что SSL сертификат не настроен.

## Решение

### 1. Установите Certbot (если еще не установлен)
```bash
sudo apt update
sudo apt install certbot python3-certbot-nginx -y
```

### 2. Получите SSL сертификат для ws.chattify.site
```bash
sudo certbot --nginx -d ws.chattify.site
```

Certbot автоматически:
- Получит SSL сертификат от Let's Encrypt
- Обновит конфигурацию nginx
- Настроит автоматическое обновление сертификата

### 3. Проверьте конфигурацию nginx
После установки сертификата проверьте файл:
```bash
sudo nano /etc/nginx/sites-available/websocket-server
```

Убедитесь, что:
- Есть блок `server` с `listen 443 ssl http2;`
- Указаны правильные пути к сертификатам:
  - `ssl_certificate /etc/letsencrypt/live/ws.chattify.site/fullchain.pem;`
  - `ssl_certificate_key /etc/letsencrypt/live/ws.chattify.site/privkey.pem;`

### 4. Проверьте конфигурацию nginx
```bash
sudo nginx -t
```

### 5. Перезапустите nginx
```bash
sudo systemctl restart nginx
```

### 6. Проверьте работу WebSocket
Откройте в браузере:
- `https://ws.chattify.site/health` - должен вернуть JSON с информацией о сервере

### 7. Обновите переменные окружения фронтенда
В файле `.env` фронтенда убедитесь, что указан правильный URL:
```env
VITE_WEBSOCKET_URL=https://ws.chattify.site
```

Или если используете домен без поддомена:
```env
VITE_WEBSOCKET_URL=wss://ws.chattify.site
```

### 8. Пересоберите фронтенд
```bash
cd social-network-frontend
npm run build
```

## Проверка работы

### Проверка SSL сертификата
```bash
openssl s_client -connect ws.chattify.site:443 -servername ws.chattify.site
```

### Проверка WebSocket соединения
В консоли браузера должно быть:
```
✅ WebSocket connected
```

Вместо:
```
❌ WebSocket connect_error: websocket error
```

## Автоматическое обновление сертификата

Certbot автоматически настроит cron задачу для обновления сертификата. Проверить можно:
```bash
sudo certbot renew --dry-run
```

## Альтернатива: Использование существующего сертификата

Если у вас уже есть SSL сертификат для основного домена (chattify.site), можно использовать его:

1. Обновите пути в nginx конфигурации:
```nginx
ssl_certificate /etc/letsencrypt/live/chattify.site/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/chattify.site/privkey.pem;
```

2. Добавьте `ws.chattify.site` в список доменов сертификата:
```bash
sudo certbot --nginx -d chattify.site -d www.chattify.site -d ws.chattify.site
```

## Troubleshooting

### Ошибка: "Connection refused"
- Проверьте, что WebSocket сервер запущен: `pm2 status`
- Проверьте, что порт 3001 открыт: `netstat -tlnp | grep 3001`

### Ошибка: "SSL certificate problem"
- Убедитесь, что DNS запись для `ws.chattify.site` указывает на правильный IP
- Проверьте, что сертификат действителен: `sudo certbot certificates`

### Ошибка: "502 Bad Gateway"
- Проверьте логи nginx: `sudo tail -f /var/log/nginx/error.log`
- Проверьте, что WebSocket сервер слушает на localhost:3001
