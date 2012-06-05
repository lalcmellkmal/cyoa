OUT = out out/server.js out/universe.js out/lua.js out/client.js out/config.js

all: $(OUT)

run: $(OUT)
	node out/server.js

out/client.js: client.coffee
	coffee -o out -c $<

out/%.js: %.js
	cp $< $@

out/%.js: %.nl
	../nestless/nestless.js $< -o $@

out:
	mkdir out

clean:
	rm -rf -- out

.PHONY: all clean
