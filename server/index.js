const express = require('express');
const { ParseServer } = require('parse-server');
const app = express();

const config = {
  databaseURI: process.env.DATABASE_URI,
  appId: process.env.APP_ID,
  masterKey: process.env.MASTER_KEY,
  serverURL: 'http://localhost:1337/parse',
  allowClientClassCreation: true,  // เปลี่ยนเป็น true
  enableAnonymousUsers: false
};

const api = new ParseServer(config);
app.use('/parse', api);

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(1337, () => {
  console.log('Parse Server running on port 1337');
  console.log('allowClientClassCreation:', config.allowClientClassCreation);
});