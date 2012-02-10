OUT = out out/server.js out/universe.js out/client.js

all: $(OUT)

run: $(OUT)
	node out/server.js

out/client.js: client.coffee
	coffee -o out -c $<

out/%.js: %.nl
	../nestless/nestless.js $< -o $@

out:
	mkdir out

clean:
	rm -rf -- out

.PHONY: all clean
