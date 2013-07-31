var express = require('express')
  , http = require('http')
  , path = require('path')
  , config = require('./config/default.json')
  , services = require('./config/services.json')
  , getServices = require('./lib/services')(services)
  , env = process.env
  , serveIndex = function(_, response) { response.sendfile(__dirname + "/public/index.html"); }
  , coffOpts = {path: path.join(__dirname, "public"), live: true, uglify: false}
  , app = express()
  , server;

var key;
for (key in config) {
  app.set(key, config[key]);
}

app
  .use(express.logger('short'))
  .use(require('express-coffee')(coffOpts))
  .use(express.static(__dirname + '/public'))
  .get("/",         serveIndex)
  .get("/services", getServices);

server = http.createServer(app);
server.listen(env.PORT || 0);

console.log("Listening on port: " + server.address().port);

