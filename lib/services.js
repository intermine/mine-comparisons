module.exports = function (services) {
  return function getServices(request, response) {
    if (!request.accepts("json")) {
      return response.send(406);
    }
    response.json(services);
  };
};
