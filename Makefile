OUT = server.js universe.js client.js

all: $(OUT)

client.js: client.coffee
	coffee -c $<

%.js: %.nl
	../nestless/nestless.js $< -o $@

clean:
	rm -f -- $(OUT)

.PHONY: all clean
