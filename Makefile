prog: src/**/*.odin
	odin build src -out:prog

run: prog
	@./prog
