const express = require('express');
const { ParseServer } = require('parse-server');

const app = express();

const parseServer = new ParseServer({
  databaseURI: process.env.DATABASE_URI,
  appId: process.env.APP_ID,
  masterKey: process.env.MASTER_KEY,
  serverURL: process.env.SERVER_URL || 'http://localhost:1337/parse',
  allowClientClassCreation: false,
  enableAnonymousUsers: false
});

// Start server
parseServer.start().then(() => {
  app.use('/parse', parseServer.app);
  
  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });
  
  app.listen(1337, () => {
    console.log('Parse Server running on port 1337');
  });
});