const express = require('express');
const { ParseServer } = require('parse-server');
const path = require('path');

const app = express();

// Parse Server Configuration
const config = {
  databaseURI: process.env.DATABASE_URI,
  appId: process.env.APP_ID,
  masterKey: process.env.MASTER_KEY,
  serverURL: process.env.SERVER_URL,
  
  // Security
  allowClientClassCreation: false,
  enableAnonymousUsers: false,
  
  // CORS
  allowOrigin: process.env.PARSE_SERVER_ALLOW_ORIGIN || '*',
  
  // Cloud Code
  cloud: './cloud/main.js',
  
  // Live Query (ปิดไว้ก่อน)
  // liveQuery: {
  //   classNames: ['Message', 'Notification'],
  //   redisURL: process.env.REDIS_URL
  // },
  
  // Cache (ปิดไว้ก่อน)
  // cacheAdapter: {
  //   module: 'parse-server/lib/Adapters/Cache/RedisCacheAdapter',
  //   options: {
  //     url: process.env.REDIS_URL
  //   }
  // },
  
  // Logs
  logsFolder: '/app/logs',
  verbose: process.env.NODE_ENV === 'development'
};

const parseServer = new ParseServer(config);

// Mount Parse Server
app.use('/parse', parseServer.app);

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    app: 'OneStack',
    version: '1.0.0'
  });
});

// Start server
const PORT = process.env.PORT || 1337;
const httpServer = require('http').createServer(app);

httpServer.listen(PORT, () => {
  console.log(`🚀 OneStack Parse Server running on port ${PORT}`);
});

// Live Query Server
ParseServer.createLiveQueryServer(httpServer, {
  redisURL: process.env.REDIS_URL
});