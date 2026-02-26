package pcl

import "core:mem"
import "core:fmt"

// parse api ///////////////////////////////////////////////////////////////////

parse_string :: proc(
    parser: ^Parser,
    str: string,
    user_data: rawptr = nil,
) -> (state: ParserState, res: ExecResult, ok: bool) {
    // create the arena for the temporary allocations (error messages)
    bytes: [4096]u8
    error_arena: mem.Arena
    mem.arena_init(&error_arena, bytes[:])
    error_allocator := mem.arena_allocator(&error_arena)

    // allocator for the exec tree
    tree_arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&tree_arena)
    defer mem.dynamic_arena_destroy(&tree_arena)
    tree_allocator := mem.dynamic_arena_allocator(&tree_arena)

    // allocator for the execution
    exec_arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&exec_arena)
    defer mem.dynamic_arena_destroy(&exec_arena)
    exec_allocator := mem.dynamic_arena_allocator(&exec_arena)

    exec_node_pool := memory_pool_create(ExecTreeNode, 0, exec_allocator)
    // This is not required because we are using an arena. However, we can use
    // the debug version to verify if some elements where not released as well
    // as knowing the number of elements allocated in total.
    defer memory_pool_destroy_debug(&exec_node_pool)

    // execute the given parser on the string and print error
    str := str
    global_state := GlobalParserState{
        rd = RecursionData{
            depth = 0,
            top_nodes = make(map[^Parser]ParseResult),
        },
        error_allocator = error_allocator,
        tree_allocator = tree_allocator, // TODO: create a node pool
        exec_allocator = exec_allocator,
        exec_node_pool = exec_node_pool,
        user_data = user_data,
    }
    defer delete(global_state.rd.top_nodes)
    state = state_create(&str, &global_state)
    defer state_destroy(&state)
    parse_result, err := parser_parse(&state, parser)

    ok = true
    if err != nil {
        switch e in err {
        case SyntaxError:
            fmt.printfln("syntax error: {}", e.message)
            state_print_context(&state)
        case InternalError:
            fmt.printfln("internal error: {}", e.message)
        }
        ok = false
    } else if !state_eof(&state) {
        fmt.printfln("syntax error: the parser did not consume all the string.")
        state_print_context(&state)
        ok = false
    } else {
        switch result in parse_result {
        case(^ExecTreeNode): res = exec_tree_exec(result, user_data, exec_allocator, &exec_node_pool)
        case(ExecResult): res = result
        }
    }
    return state, res, ok
}
