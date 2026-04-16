package pcl

import "core:mem"
import "core:fmt"
import "core:os"

PCLHandle :: struct {
    // TODO: error_stack: [dynamic]ParserError
    branch_depth: u64,
    lrec_depth: u64,
    do_not_exec: bool,
    error_allocator: mem.Allocator,
    // parser allocator
    parser_arena: mem.Dynamic_Arena,
    parser_allocator: mem.Allocator,
    // result allocator
    result_arena: mem.Dynamic_Arena,
    result_allocator: mem.Allocator,
    // exec tree allocator
    exec_arena: mem.Dynamic_Arena,
    exec_allocator: mem.Allocator,
    exec_node_pool: MemoryPool(ExecTreeNode),
    // other infos
    user_data: rawptr,
    current_grammar: ^Parser,
}

handle_create :: proc() -> (handle: ^PCLHandle) {
    handle = new(PCLHandle)

    // allocator for the parser graph (optionaly used by the user)
    mem.dynamic_arena_init(&handle.parser_arena)
    handle.parser_allocator = mem.dynamic_arena_allocator(&handle.parser_arena)

    // allocator for the exec tree
    mem.dynamic_arena_init(&handle.result_arena)
    handle.result_allocator = mem.dynamic_arena_allocator(&handle.result_arena)

    // allocator for the execution
    mem.dynamic_arena_init(&handle.exec_arena)
    handle.exec_allocator = mem.dynamic_arena_allocator(&handle.exec_arena)

    handle.exec_node_pool = memory_pool_create(ExecTreeNode, 0, handle.exec_allocator)
    return handle
}

handle_destroy :: proc(handle: ^PCLHandle) {
    memory_pool_destroy(&handle.exec_node_pool)
    mem.dynamic_arena_destroy(&handle.exec_arena)
    mem.dynamic_arena_destroy(&handle.result_arena)
    mem.dynamic_arena_destroy(&handle.parser_arena)
    free(handle)
}

handle_reset :: proc(handle: ^PCLHandle) {
    free_all(handle.result_allocator)
    free_all(handle.exec_allocator)
    handle.exec_node_pool = memory_pool_create(ExecTreeNode, 0, handle.exec_allocator)
}

handle_grammar :: proc(handle: ^PCLHandle) -> ^Parser {
    return handle.current_grammar
}

handle_parser_allocator :: proc(handle: ^PCLHandle) -> mem.Allocator {
    return handle.parser_allocator
}

// parse api ///////////////////////////////////////////////////////////////////

parse_string :: proc(
    handle: ^PCLHandle,
    parser: ^Parser,
    str: ^string,
    user_data: rawptr = nil,
) -> (res: ExecResult, ok: bool) {
    // set the user data
    handle.user_data = user_data
    handle.current_grammar = parser

    // create the arena for the temporary allocations (error messages)
    bytes: [4096]u8
    error_arena: mem.Arena
    mem.arena_init(&error_arena, bytes[:])
    handle.error_allocator = mem.arena_allocator(&error_arena)
    defer handle.error_allocator = mem.Allocator{}

    // execute the given parser on the string and print error
    global_state := ParserGlobalState{
        content = str^,
        handle = handle,
    }
    state := state_create(&global_state)
    parse_result, err := parser_parse(&state, parser)

    // make sure there are no trailing skipable runes
    parser_skip(&state, SKIP)

    ok = true
    if err != nil {
        parser_error_report(err)
        ok = false
    } else if !state_eof(&state) {
        fmt.printfln("syntax error: the parser did not consume all the string.")
        state_print_context(&state)
        ok = false
    } else {
        switch result in parse_result {
        case(^ExecTreeNode): res = exec_tree_exec(result, user_data,
                                                  handle.exec_allocator,
                                                  &handle.exec_node_pool)
        case(ExecResult): res = result
        }
    }
    return res, ok
}

// Since the parser can generate tokens that contain substrings that are just
// slices of the whole parsed string, the lifetime of the file content should
// be extended to the outer scope of this function.
parse_file :: proc(
    handle: ^PCLHandle,
    parser: ^Parser,
    filepath: string,
    user_data: rawptr = nil,
    allocator := context.allocator, // we need to create the string
) -> (filecontent: string, res: ExecResult, ok: bool) {
	data, err := os.read_entire_file(filepath, allocator)
	if err != nil {
		// could not read file
		return
	}
    filecontent = string(data)
    res, ok = parse_string(handle, parser, &filecontent, user_data)
    return filecontent, res, ok
}
