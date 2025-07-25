#!/bin/bash

# Скрипт для развертывания WebSocket сервера на VPS
# Запускать от имени root или с sudo

echo "🚀 Начинаем развертывание WebSocket сервера..."

# Обновляем систему
echo "📦 Обновляем систему..."
apt update && apt upgrade -y

# Устанавливаем Node.js и npm
echo "📦 Устанавливаем Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt-get install -y nodejs

# Устанавливаем PM2 для управления процессами
echo "📦 Устанавливаем PM2..."
npm install -g pm2

# Устанавливаем nginx
echo "📦 Устанавливаем nginx..."
apt install nginx -y

# Создаем пользователя для приложения
echo "👤 Создаем пользователя websocket..."
useradd -m -s /bin/bash websocket
usermod -aG sudo websocket

# Переключаемся на пользователя websocket
echo "📁 Настраиваем рабочую директорию..."
su - websocket << 'EOF'

# Создаем директорию для приложения
mkdir -p ~/websocket-server
cd ~/websocket-server

# Клонируем репозиторий (замените на ваш URL)
# git clone https://github.com/your-username/your-repo.git .

# Или копируем файлы вручную
echo "📋 Создаем файлы приложения..."

# Создаем package.json
cat > package.json << 'PACKAGE_EOF'
{
  "name": "websocket-server",
  "version": "1.0.0",
  "description": "WebSocket server for real-time features",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "pm2:start": "pm2 start server.js --name websocket-server",
    "pm2:stop": "pm2 stop websocket-server",
    "pm2:restart": "pm2 restart websocket-server",
    "pm2:logs": "pm2 logs websocket-server"
  },
  "dependencies": {
    "express": "^4.18.2",
    "socket.io": "^4.7.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "axios": "^1.5.0",
    "jsonwebtoken": "^9.0.2"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  },
  "engines": {
    "node": ">=16.0.0"
  }
}
PACKAGE_EOF

# Создаем .env файл
cat > .env << 'ENV_EOF'
# WebSocket Server Configuration
PORT=3001
NODE_ENV=production

# CORS Configuration - добавляем все возможные домены
ALLOWED_ORIGINS=https://chattify.site,https://www.chattify.site,https://chattify.space,https://www.chattify.space,http://localhost:3000,http://localhost:3001

# Laravel Backend URL
LARAVEL_API_URL=https://chattify.space

# Logging
LOG_LEVEL=info
ENV_EOF

# Создаем server.js (основной файл сервера)
cat > server.js << 'SERVER_EOF'
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const axios = require('axios');
require('dotenv').config();

const app = express();
const server = http.createServer(app);

// Расширенная конфигурация CORS
const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || [
  'https://chattify.site',
  'https://www.chattify.site',
  'https://chattify.space',
  'https://www.chattify.space',
  'http://localhost:3000',
  'http://localhost:3001'
];

console.log('🔗 Разрешенные домены для CORS:', allowedOrigins);

const io = socketIo(server, {
  cors: {
    origin: function (origin, callback) {
      // Разрешаем запросы без origin (например, мобильные приложения)
      if (!origin) return callback(null, true);
      
      if (allowedOrigins.indexOf(origin) !== -1) {
        callback(null, true);
      } else {
        console.log('🚫 CORS заблокирован для:', origin);
        callback(new Error('Not allowed by CORS'));
      }
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    credentials: true
  },
  transports: ['websocket', 'polling'],
  allowEIO3: true
});

// Хранилище подключенных пользователей
const connectedUsers = new Map();
const userSockets = new Map();

// Middleware для аутентификации
io.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth.token || socket.handshake.headers.authorization;
    
    if (!token) {
      console.log('❌ No token provided');
      return next(new Error('Authentication error: No token provided'));
    }

    // Убираем 'Bearer ' если есть
    const cleanToken = token.replace('Bearer ', '');
    
    // Проверяем токен через Laravel API с увеличенным таймаутом
    try {
      const response = await axios.get(`${process.env.LARAVEL_API_URL}/api/profile`, {
        headers: {
          'Authorization': `Bearer ${cleanToken}`,
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        timeout: 10000 // Увеличиваем таймаут до 10 секунд
      });

      if (response.status === 200 && response.data) {
        socket.userId = response.data.id;
        socket.user = response.data;
        
        console.log(`✅ User ${response.data.id} authenticated successfully`);
        return next();
      } else {
        console.log('❌ Invalid response from Laravel API');
        return next(new Error('Authentication error: Invalid response from API'));
      }
    } catch (apiError) {
      console.log(`❌ API authentication error: ${apiError.message}`);
      
      // Если API недоступен, разрешаем подключение без аутентификации для отладки
      if (process.env.NODE_ENV === 'development') {
        console.log('⚠️ Development mode: allowing connection without authentication');
        socket.userId = 'debug_user';
        socket.user = { id: 'debug_user', name: 'Debug User' };
        return next();
      }
      
      return next(new Error('Authentication error: API unavailable'));
    }
  } catch (error) {
    console.error('❌ Authentication middleware error:', error.message);
    return next(new Error('Authentication error: ' + error.message));
  }
});

// Middleware CORS для Express
app.use(cors({
  origin: function (origin, callback) {
    // Разрешаем запросы без origin
    if (!origin) return callback(null, true);
    
    if (allowedOrigins.indexOf(origin) !== -1) {
      callback(null, true);
    } else {
      console.log('🚫 Express CORS заблокирован для:', origin);
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
}));

app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    allowedOrigins: allowedOrigins,
    connectedUsers: connectedUsers.size
  });
});

// Обработка подключения
io.on('connection', (socket) => {
  console.log(`🔌 User ${socket.userId} connected (Socket ID: ${socket.id})`);
  
  // Сохраняем информацию о подключенном пользователе
  connectedUsers.set(socket.userId, {
    id: socket.userId,
    socketId: socket.id,
    connectedAt: new Date(),
    user: socket.user
  });
  
  // Сохраняем сокет пользователя
  if (!userSockets.has(socket.userId)) {
    userSockets.set(socket.userId, []);
  }
  userSockets.get(socket.userId).push(socket.id);
  
  // Уведомляем всех о том, что пользователь онлайн
  socket.broadcast.emit('user:online', {
    userId: socket.userId,
    user: socket.user
  });
  
  // Подписываем пользователя на его личные каналы
  socket.join(`user:${socket.userId}`);
  socket.join('public');
  
  console.log(`📡 User ${socket.userId} joined channels: user:${socket.userId}, public`);
  console.log(`👥 Total connected users: ${connectedUsers.size}`);
  
  // Обработка тестовых событий
  socket.on('test', (data) => {
    console.log(`🧪 Test event from user ${socket.userId}:`, data);
    socket.emit('test_response', { 
      message: 'Test received successfully',
      timestamp: new Date().toISOString(),
      user: socket.user
    });
  });
  
  // Присоединение к комнате
  socket.on('join', (data) => {
    if (data.room) {
      socket.join(data.room);
      console.log(`🔗 User ${socket.userId} joined room: ${data.room}`);
      socket.emit('room_joined', { room: data.room });
    }
  });
  
  // Выход из комнаты
  socket.on('leave', (data) => {
    if (data.room) {
      socket.leave(data.room);
      console.log(`🔗 User ${socket.userId} left room: ${data.room}`);
      socket.emit('room_left', { room: data.room });
    }
  });
  
  // Обработка отключения
  socket.on('disconnect', () => {
    console.log(`🔌 User ${socket.userId} disconnected (Socket ID: ${socket.id})`);
    
    // Удаляем сокет из списка
    const userSocketIds = userSockets.get(socket.userId);
    if (userSocketIds) {
      const index = userSocketIds.indexOf(socket.id);
      if (index > -1) {
        userSocketIds.splice(index, 1);
      }
      
      // Если у пользователя больше нет активных сокетов
      if (userSocketIds.length === 0) {
        userSockets.delete(socket.userId);
        connectedUsers.delete(socket.userId);
        
        // Уведомляем всех о том, что пользователь оффлайн
        socket.broadcast.emit('user:offline', {
          userId: socket.userId
        });
        
        console.log(`👤 User ${socket.userId} went offline`);
      }
    }
    
    console.log(`👥 Total connected users: ${connectedUsers.size}`);
  });
});

// Получение списка онлайн пользователей
app.get('/api/online-users', (req, res) => {
  const onlineUsers = Array.from(connectedUsers.values()).map(user => ({
    id: user.id,
    name: user.user.name,
    connectedAt: user.connectedAt
  }));
  
  console.log(`📊 Online users request: ${onlineUsers.length} users`);
  
  res.json({
    success: true,
    data: onlineUsers,
    count: onlineUsers.length
  });
});

// Отправка события всем пользователям
app.post('/api/broadcast', (req, res) => {
  const { event, data, channel = 'public' } = req.body;
  
  if (!event) {
    console.log('❌ Broadcast request missing event name');
    return res.status(400).json({
      success: false,
      message: 'Event name is required'
    });
  }
  
  console.log(`📡 Broadcasting event '${event}' to channel '${channel}'`);
  io.to(channel).emit(event, data);
  
  res.json({
    success: true,
    message: `Event ${event} broadcasted to channel ${channel}`
  });
});

// Отправка события конкретному пользователю
app.post('/api/send-to-user', (req, res) => {
  const { userId, event, data } = req.body;
  
  if (!userId || !event) {
    console.log('❌ Send-to-user request missing userId or event');
    return res.status(400).json({
      success: false,
      message: 'User ID and event name are required'
    });
  }
  
  console.log(`📡 Sending event '${event}' to user ${userId}`);
  io.to(`user:${userId}`).emit(event, data);
  
  res.json({
    success: true,
    message: `Event ${event} sent to user ${userId}`
  });
});

// Специальный endpoint для событий постов
app.post('/api/posts/broadcast', (req, res) => {
  const { type, data } = req.body;
  
  if (!type) {
    console.log('❌ Posts broadcast request missing type');
    return res.status(400).json({
      success: false,
      message: 'Event type is required'
    });
  }
  
  console.log(`📝 Posts broadcast request: ${type}`, data);
  
  try {
    switch (type) {
      case 'new_post':
        // Отправляем всем пользователям
        console.log(`📡 Broadcasting new post to all users`);
        console.log('📊 Post data being sent:', {
          post: data.post,
          post_id: data.post?.id,
          user_id: data.post?.user_id,
          content: data.post?.content
        });
        io.to('public').emit('post:created', {
          post: data.post
        });
        break;
        
      case 'post_updated':
        // Отправляем всем пользователям
        console.log(`✏️ Broadcasting post updated to all users`);
        io.to('public').emit('post:updated', {
          post: data.post
        });
        break;
        
      case 'post_liked':
        // Отправляем всем пользователям для обновления UI
        console.log(`❤️ Broadcasting like to all users`);
        console.log('📊 Like data:', {
          post_id: data.post_id,
          like_id: data.like_id,
          user_id: data.user_id,
          status: data.status,
          reaction_type: data.reaction_type,
          user: data.user
        });
        io.to('public').emit('post:liked', {
          post_id: data.post_id,
          like_id: data.like_id,
          user_id: data.user_id,
          status: data.status,
          reaction_type: data.reaction_type,
          user: data.user
        });
        break;
        
      case 'post_commented':
        // Отправляем всем пользователям для отображения комментария в реальном времени
        console.log(`💬 Broadcasting comment to all users`);
        console.log('📊 Comment data:', {
          comment_id: data.comment_id,
          post_id: data.post_id,
          user_id: data.user_id,
          content: data.content,
          image_path: data.image_path,
          parent_id: data.parent_id,
          created_at: data.created_at,
          updated_at: data.updated_at,
          user: data.user,
          mentions: data.mentions
        });
        io.to('public').emit('post:commented', {
          comment_id: data.comment_id,
          post_id: data.post_id,
          user_id: data.user_id,
          content: data.content,
          image_path: data.image_path,
          parent_id: data.parent_id,
          created_at: data.created_at,
          updated_at: data.updated_at,
          user: data.user,
          mentions: data.mentions || [],
          comment: data.comment || null // Добавляем полный объект комментария если есть
        });
        break;
        
      case 'post_deleted':
        // Отправляем всем пользователям
        console.log(`🗑️ Broadcasting post deleted to all users`);
        io.to('public').emit('post:deleted', {
          post_id: data.post_id,
          user_id: data.user_id
        });
        break;
        
      case 'comment_deleted':
        // Отправляем всем пользователям
        console.log(`🗑️ Broadcasting comment deleted to all users`);
        io.to('public').emit('comment:deleted', {
          comment_id: data.comment_id,
          post_id: data.post_id,
          user_id: data.user_id
        });
        break;
        
      case 'comment_liked':
        // Отправляем всем пользователям
        console.log(`❤️ Broadcasting comment like to all users`);
        io.to('public').emit('comment:liked', {
          like_id: data.like_id,
          comment_id: data.comment_id,
          post_id: data.post_id,
          user_id: data.user_id,
          status: data.status,
          user: data.user
        });
        break;
        
      case 'poll_voted':
        // Отправляем всем пользователям для обновления результатов опроса
        console.log(`🗳️ Broadcasting poll vote to all users`);
        console.log('📊 Poll vote data:', {
          poll_id: data.poll_id,
          post_id: data.post_id,
          option_id: data.option_id,
          user_id: data.user_id,
          poll: data.poll
        });
        io.to('public').emit('poll:voted', {
          poll_id: data.poll_id,
          post_id: data.post_id,
          option_id: data.option_id,
          user_id: data.user_id,
          poll: data.poll
        });
        break;
        
      case 'poll_created':
        // Отправляем всем пользователям
        console.log(`📊 Broadcasting new poll to all users`);
        io.to('public').emit('poll:created', {
          poll_id: data.poll_id,
          post_id: data.post_id,
          poll: data.poll
        });
        break;
        
      case 'poll_updated':
        // Отправляем всем пользователям
        console.log(`📊 Broadcasting poll update to all users`);
        io.to('public').emit('poll:updated', {
          poll_id: data.poll_id,
          post_id: data.post_id,
          poll: data.poll
        });
        break;
        
      default:
        console.log(`❌ Unknown post event type: ${type}`);
        return res.status(400).json({
          success: false,
          message: 'Unknown event type'
        });
    }
    
    console.log(`✅ Post event ${type} broadcasted successfully`);
    res.json({
      success: true,
      message: `Post event ${type} broadcasted successfully`
    });
    
  } catch (error) {
    console.error('❌ Error broadcasting post event:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Специальный endpoint для событий пользователей
app.post('/api/users/broadcast', (req, res) => {
  const { type, data } = req.body;
  
  if (!type) {
    console.log('❌ Users broadcast request missing type');
    return res.status(400).json({
      success: false,
      message: 'Event type is required'
    });
  }
  
  console.log(`👤 Users broadcast request: ${type}`, data);
  
  try {
    switch (type) {
      case 'user_status_changed':
        // Отправляем всем пользователям
        console.log(`👤 Broadcasting user status change to all users`);
        console.log('📊 User status data:', {
          user_id: data.user_id,
          user_name: data.user_name,
          status: data.status,
          is_online: data.is_online,
          last_activity: data.last_activity
        });
        io.to('public').emit('user:status_changed', {
          user_id: data.user_id,
          user_name: data.user_name,
          status: data.status,
          is_online: data.is_online,
          last_activity: data.last_activity,
          user: data.user
        });
        break;
        
      default:
        console.log(`❌ Unknown user event type: ${type}`);
        return res.status(400).json({
          success: false,
          message: 'Unknown event type'
        });
    }
    
    console.log(`✅ User event ${type} broadcasted successfully`);
    res.json({
      success: true,
      message: `User event ${type} broadcasted successfully`
    });
    
  } catch (error) {
    console.error('❌ Error broadcasting user event:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Специальный endpoint для событий чатов
app.post('/api/chats/broadcast', (req, res) => {
  const { type, data } = req.body;
  
  if (!type) {
    console.log('❌ Chats broadcast request missing type');
    return res.status(400).json({
      success: false,
      message: 'Event type is required'
    });
  }
  
  console.log(`💬 Chats broadcast request: ${type}`, data);
  
  try {
    switch (type) {
      case 'chat_message_sent':
        // Отправляем в конкретный чат
        console.log(`💬 Broadcasting new message to chat ${data.chat_id}`);
        console.log('📊 Chat message data:', {
          message_id: data.message_id,
          chat_id: data.chat_id,
          sender_id: data.sender_id,
          content: data.content,
          attachment: data.attachment,
          reply_to: data.reply_to,
          is_forwarded: data.is_forwarded,
          original_sender_id: data.original_sender_id,
          created_at: data.created_at,
          updated_at: data.updated_at,
          sender: data.sender
        });
        
        // Проверяем, есть ли пользователи в комнате
        const room = io.sockets.adapter.rooms.get(`chat.${data.chat_id}`);
        console.log(`👥 Users in room chat.${data.chat_id}:`, room ? room.size : 0);
        
        io.to(`chat.${data.chat_id}`).emit('chat:message_sent', {
          message_id: data.message_id,
          chat_id: data.chat_id,
          sender_id: data.sender_id,
          content: data.content,
          attachment: data.attachment,
          reply_to: data.reply_to,
          is_forwarded: data.is_forwarded,
          original_sender_id: data.original_sender_id,
          created_at: data.created_at,
          updated_at: data.updated_at,
          sender: data.sender
        });
        
        console.log(`✅ Message broadcasted to room chat.${data.chat_id}`);
        break;
        
      case 'chat_message_edited':
        // Отправляем в конкретный чат
        console.log(`✏️ Broadcasting message edited to chat ${data.chat_id}`);
        io.to(`chat.${data.chat_id}`).emit('chat:message_edited', {
          message_id: data.message_id,
          chat_id: data.chat_id,
          sender_id: data.sender_id,
          content: data.content,
          updated_at: data.updated_at,
          is_edited: data.is_edited
        });
        break;
        
      case 'chat_message_deleted':
        // Отправляем в конкретный чат
        console.log(`🗑️ Broadcasting message deleted to chat ${data.chat_id}`);
        io.to(`chat.${data.chat_id}`).emit('chat:message_deleted', {
          message_id: data.message_id,
          chat_id: data.chat_id,
          sender_id: data.sender_id
        });
        break;
        
      case 'chat_message_reaction':
        // Отправляем в конкретный чат
        console.log(`❤️ Broadcasting message reaction to chat ${data.chat_id}`);
        io.to(`chat.${data.chat_id}`).emit('chat:message_reaction', {
          message_id: data.message_id,
          chat_id: data.chat_id,
          reaction: data.reaction,
          action: data.action,
          reactions: data.reactions,
          updated_at: data.updated_at
        });
        break;
        
      case 'user_typing':
        // Отправляем в конкретный чат
        console.log(`⌨️ Broadcasting user typing to chat ${data.chat_id}`);
        io.to(`chat.${data.chat_id}`).emit('chat:user_typing', {
          user_id: data.user_id,
          chat_id: data.chat_id,
          is_typing: data.is_typing,
          timestamp: data.timestamp
        });
        break;
        
      case 'messages_read':
        // Отправляем в конкретный чат
        console.log(`👁️ Broadcasting messages read to chat ${data.chat_id}`);
        io.to(`chat.${data.chat_id}`).emit('chat:messages_read', {
          chat_id: data.chat_id,
          user_id: data.user_id,
          message_ids: data.message_ids,
          timestamp: data.timestamp
        });
        break;
        
      default:
        console.log(`❌ Unknown chat event type: ${type}`);
        return res.status(400).json({
          success: false,
          message: 'Unknown event type'
        });
    }
    
    console.log(`✅ Chat event ${type} broadcasted successfully`);
    res.json({
      success: true,
      message: `Chat event ${type} broadcasted successfully`
    });
    
  } catch (error) {
    console.error('❌ Error broadcasting chat event:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Специальный endpoint для событий уведомлений
app.post('/api/notifications/broadcast', (req, res) => {
  const { type, data } = req.body;
  
  if (!type) {
    console.log('❌ Notifications broadcast request missing type');
    return res.status(400).json({
      success: false,
      message: 'Event type is required'
    });
  }
  
  console.log(`🔔 Notifications broadcast request: ${type}`, data);
  
  try {
    switch (type) {
      case 'notification_created':
        // Отправляем конкретному пользователю
        console.log(`🔔 Broadcasting new notification to user ${data.user_id}`);
        io.to(`user:${data.user_id}`).emit('notification:created', {
          notification_id: data.notification_id,
          user_id: data.user_id,
          type: data.type,
          data: data.data,
          created_at: data.created_at
        });
        break;
        
      case 'notification_read':
        // Отправляем конкретному пользователю
        console.log(`👁️ Broadcasting notification read to user ${data.user_id}`);
        io.to(`user:${data.user_id}`).emit('notification:read', {
          notification_id: data.notification_id,
          user_id: data.user_id,
          read_at: data.read_at
        });
        break;
        
      case 'notifications_read_all':
        // Отправляем конкретному пользователю
        console.log(`👁️ Broadcasting all notifications read to user ${data.user_id}`);
        io.to(`user:${data.user_id}`).emit('notifications:read_all', {
          user_id: data.user_id,
          read_at: data.read_at
        });
        break;
        
      default:
        console.log(`❌ Unknown notification event type: ${type}`);
        return res.status(400).json({
          success: false,
          message: 'Unknown event type'
        });
    }
    
    console.log(`✅ Notification event ${type} broadcasted successfully`);
    res.json({
      success: true,
      message: `Notification event ${type} broadcasted successfully`
    });
    
  } catch (error) {
    console.error('❌ Error broadcasting notification event:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

const PORT = process.env.PORT || 3001;

server.listen(PORT, () => {
  console.log(`🚀 WebSocket server running on port ${PORT}`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV}`);
  console.log(`🔗 Laravel API URL: ${process.env.LARAVEL_API_URL}`);
  console.log(`🌐 CORS Origin: ${process.env.ALLOWED_ORIGINS}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('🛑 SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('✅ Process terminated');
  });
});
SERVER_EOF

# Устанавливаем зависимости
echo "📦 Устанавливаем зависимости..."
npm install

# Создаем PM2 ecosystem файл
cat > ecosystem.config.js << 'ECOSYSTEM_EOF'
module.exports = {
  apps: [{
    name: 'websocket-server',
    script: 'server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3001
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true
  }]
};
ECOSYSTEM_EOF

# Создаем директорию для логов
mkdir -p logs

# Останавливаем существующие процессы PM2
echo "🛑 Останавливаем существующие процессы..."
pm2 delete websocket-server 2>/dev/null || true

# Запускаем приложение через PM2
echo "🚀 Запускаем WebSocket сервер через PM2..."
pm2 start ecosystem.config.js

# Проверяем статус
echo "📊 Проверяем статус PM2..."
pm2 status

# Сохраняем PM2 конфигурацию
pm2 save

# Настраиваем автозапуск PM2
pm2 startup

echo "✅ WebSocket сервер запущен!"

# Показываем логи для проверки
echo "📋 Последние логи сервера:"
pm2 logs websocket-server --lines 10

EOF

# Настраиваем nginx
echo "🌐 Настраиваем nginx..."
cat > /etc/nginx/sites-available/websocket-server << 'NGINX_EOF'
server {
    listen 80;
    server_name ws.chattify.site;  # Замените на ваш домен для WebSocket

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
        proxy_set_header X-Forwarded-Proto $scheme;
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
        proxy_set_header X-Forwarded-Proto $scheme;
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
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX_EOF

# Активируем сайт
ln -sf /etc/nginx/sites-available/websocket-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверяем конфигурацию nginx
echo "🔍 Проверяем конфигурацию nginx..."
nginx -t

# Перезапускаем nginx
systemctl restart nginx
systemctl enable nginx

# Проверяем статус nginx
echo "📊 Статус nginx:"
systemctl status nginx --no-pager -l

# Настраиваем firewall
echo "🔥 Настраиваем firewall..."
ufw allow ssh
ufw allow 80
ufw allow 443
ufw --force enable

# Проверяем статус PM2 от имени root
echo "📊 Проверяем статус PM2 (root):"
pm2 status

echo "🎉 Развертывание завершено!"
echo "📋 Следующие шаги:"
echo "1. Настройте DNS для ws.chattify.site на IP этого сервера"
echo "2. Обновите .env файлы в Laravel и React приложениях"
echo "3. Настройте SSL сертификат для ws.chattify.site"
echo ""
echo "🔍 Для проверки работы сервера:"
echo "- PM2 статус: pm2 status"
echo "- PM2 логи: pm2 logs websocket-server"
echo "- Проверка порта: netstat -tlnp | grep 3001"
echo "- Проверка nginx: systemctl status nginx" 