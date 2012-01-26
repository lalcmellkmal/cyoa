all: server.js client.js

client.js:
	coffee -c client.coffee

server.js: server.nl
	../nestless/nestless.js $< -o $@

.PHONY: server.js
