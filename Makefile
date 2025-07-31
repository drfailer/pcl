prog: src/main.odin src/**/*.odin
	odin build src -out:prog

run: prog
	@./prog
