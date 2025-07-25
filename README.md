# WebSocket Server для Социальной Сети

Этот WebSocket сервер на Node.js работает в связке с Laravel API для обеспечения real-time функциональности в социальной сети.

## Архитектура

```
React Frontend (Port 3000)
    ↓ HTTP/HTTPS
Laravel API (Port 8000)
    ↓ HTTP API
Node.js WebSocket Server (Port 3001)
    ↓ WebSocket
React Frontend (Port 3000)
```

## Установка и настройка

### 1. Установка зависимостей

```bash
cd websocket-server
npm install
```

### 2. Настройка переменных окружения

Скопируйте файл `env.example` в `.env` и настройте переменные:

```bash
cp env.example .env
```

Отредактируйте `.env` файл:

```env
# WebSocket Server Configuration
PORT=3001
NODE_ENV=development

# JWT Secret (должен совпадать с секретом в Laravel)
JWT_SECRET=your-jwt-secret-key

# CORS Configuration
CORS_ORIGIN=http://localhost:3000

# Laravel API URL
LARAVEL_API_URL=http://localhost:8000
```

### 3. Запуск сервера

```bash
# Разработка
npm run dev

# Продакшн
npm start
```

## Функциональность

### Поддерживаемые события постов

1. **Новые посты**
   - `post:created` - создан новый пост

2. **Лайки**
   - `post:liked` - поставлен лайк на пост

3. **Комментарии**
   - `post:commented` - добавлен комментарий к посту

### API Endpoints

#### GET /api/online-users
Получить список онлайн пользователей

```bash
curl http://localhost:3001/api/online-users
```

#### POST /api/posts/broadcast
Отправить событие поста

```bash
curl -X POST http://localhost:3001/api/posts/broadcast \
  -H "Content-Type: application/json" \
  -d '{
    "type": "new_post",
    "data": {
      "post_id": 123,
      "user_id": 456,
      "content": "Текст поста",
      "user": {
        "id": 456,
        "name": "Имя пользователя"
      }
    }
  }'
```

#### POST /api/broadcast
Отправить событие всем пользователям

```bash
curl -X POST http://localhost:3001/api/broadcast \
  -H "Content-Type: application/json" \
  -d '{
    "event": "custom_event",
    "data": {"message": "Hello world"},
    "channel": "public"
  }'
```

#### POST /api/send-to-user
Отправить событие конкретному пользователю

```bash
curl -X POST http://localhost:3001/api/send-to-user \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 123,
    "event": "private_message",
    "data": {"message": "Private message"}
  }'
```

## Интеграция с Laravel

### 1. Настройка Laravel

В файле `.env` Laravel добавьте:

```env
WEBSOCKET_SERVER_URL=http://localhost:3001
```

### 2. Использование WebSocketService

```php
use App\Services\WebSocketService;

// Отправить событие о новом посте
WebSocketService::newPost($post);

// Отправить событие о лайке
WebSocketService::newLike($like, $postOwnerId);

// Отправить событие о комментарии
WebSocketService::newComment($comment, $postOwnerId);

// Отправить событие конкретному пользователю
WebSocketService::sendToUser($userId, 'custom_event', $data);

// Получить список онлайн пользователей
$onlineUsers = WebSocketService::getOnlineUsers();
```

## Интеграция с React

### 1. Добавление переменной окружения

В файле `.env` React приложения добавьте:

```env
REACT_APP_WEBSOCKET_URL=http://localhost:3001
```

### 2. Использование WebSocket хука

```jsx
import useWebSocket from './hooks/useWebSocket';

function MyComponent() {
  const { isConnected, onlineUsers, lastMessage } = useWebSocket();

  return (
    <div>
      <p>Статус: {isConnected ? 'Подключен' : 'Отключен'}</p>
      <p>Онлайн пользователей: {onlineUsers.length}</p>
    </div>
  );
}
```

### 3. Компонент уведомлений

```jsx
import PostNotifications from './components/PostNotifications';

function App() {
  return (
    <div>
      {/* Ваше приложение */}
      <PostNotifications />
    </div>
  );
}
```

## Тестирование

### 1. Тест WebSocket сервера

```bash
# Проверка статуса сервера
curl http://localhost:3001/api/online-users

# Тест отправки события
curl -X POST http://localhost:3001/api/posts/broadcast \
  -H "Content-Type: application/json" \
  -d '{
    "type": "new_post",
    "data": {
      "post_id": 1,
      "user_id": 1,
      "content": "Тестовый пост",
      "user": {
        "id": 1,
        "name": "Тестовый пользователь"
      }
    }
  }'
```

### 2. Тест из Laravel

```php
// В tinker или контроллере
use App\Services\WebSocketService;

// Тест отправки события
$result = WebSocketService::broadcast('test_event', ['message' => 'Hello from Laravel']);
var_dump($result); // должно вернуть true
```

## Мониторинг и логирование

Сервер автоматически логирует:
- Подключения/отключения пользователей
- Ошибки аутентификации
- HTTP запросы от Laravel
- Ошибки отправки событий

## Безопасность

- JWT аутентификация для всех WebSocket соединений
- CORS настройки для защиты от несанкционированных запросов
- Валидация всех входящих данных
- Логирование подозрительной активности

## Troubleshooting

### Проблемы с подключением

1. Проверьте, что WebSocket сервер запущен на порту 3001
2. Убедитесь, что JWT_SECRET совпадает в Laravel и Node.js
3. Проверьте CORS настройки

### Проблемы с аутентификацией

1. Проверьте формат JWT токена
2. Убедитесь, что токен не истек
3. Проверьте JWT_SECRET

### Проблемы с событиями

1. Проверьте подключение к WebSocket серверу
2. Убедитесь, что события отправляются в правильный endpoint
3. Проверьте логи сервера

### Проблемы с Laravel

1. Проверьте переменную WEBSOCKET_SERVER_URL в .env
2. Убедитесь, что WebSocketService правильно импортирован
3. Проверьте логи Laravel на ошибки HTTP запросов 