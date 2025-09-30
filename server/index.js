const express = require('express');
const { ParseServer } = require('parse-server');
const path = require('path');

const app = express();

const config = {
  databaseURI: process.env.DATABASE_URI,
  appId: process.env.APP_ID,
  masterKey: process.env.MASTER_KEY,
  serverURL: process.env.SERVER_URL || 'http://localhost:1337/parse',
  
  // Security
  allowClientClassCreation: process.env.PARSE_SERVER_ALLOW_CLIENT_CLASS_CREATION === 'true',
  enableAnonymousUsers: process.env.PARSE_SERVER_ENABLE_ANON_USERS === 'true',
  
  // CORS
  allowOrigin: process.env.PARSE_SERVER_ALLOW_ORIGIN || '*',
  
  // Cloud Code (optional)
  cloud: './cloud/main.js',
  
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