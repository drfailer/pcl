package pcl

import "core:mem"

Handle :: struct {
    parser_arena: mem.Dynamic_Arena,
    parser_allocator: mem.Allocator,
    make_grammar: proc(handle: ^Handle, grammar_proc: proc() -> ^Parser, skip: SkipProc = nil) -> ^Parser,
}

create :: proc() -> (handle: ^Handle) {
    handle = new(Handle)
    mem.dynamic_arena_init(&handle.parser_arena)
    handle.parser_allocator = mem.dynamic_arena_allocator(&handle.parser_arena)
    handle.make_grammar = make_grammar
    return handle
}

destroy :: proc(handle: ^Handle) {
    mem.dynamic_arena_destroy(&handle.parser_arena)
    free(handle)
}

make_grammar :: proc(
    handle: ^Handle,
    grammar_proc: proc() -> ^Parser,
    skip: SkipProc = nil,
) -> ^Parser {
    if skip != nil {
        SKIP = skip
    }
    context.allocator = handle.parser_allocator
    return grammar_proc()
}

