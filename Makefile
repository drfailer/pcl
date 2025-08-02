prog: src/main.odin src/**/*.odin
	odin build src -out:prog

test: src/main.odin src/**/*.odin
	odin test src

run: prog
	@./prog
