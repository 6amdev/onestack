const express = require('express');
const { ParseServer } = require('parse-server');

const app = express();

const api = new ParseServer({
  databaseURI: process.env.DATABASE_URI || 'mongodb://localhost:27017/dev',
  appId: process.env.APP_ID || 'myAppId',
  masterKey: process.env.MASTER_KEY || 'myMasterKey',
  serverURL: process.env.SERVER_URL || 'http://localhost:1337/parse',
  allowClientClassCreation: true
});

// Serve the Parse API on the /parse URL prefix
api.start().then(() => {
  app.use('/parse', api.app);

  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });

  const PORT = process.env.PORT || 1337;
  app.listen(PORT, function() {
    console.log('Parse Server running on port ' + PORT);
  });
});