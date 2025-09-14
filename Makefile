prog: src/main.odin src/**/*.odin
	odin build src -out:prog -thread-count:2

test: src/main.odin src/**/*.odin
	odin test src

run: prog
	@./prog
