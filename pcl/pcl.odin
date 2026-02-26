package pcl

import "core:mem"
import "core:fmt"

PCLHandle :: struct {
    // TODO: error_stack: [dynamic]ParserError
    rd: RecursionData,
    branch_depth: u64,
    error_allocator: mem.Allocator,
    tree_arena: mem.Dynamic_Arena,
    tree_allocator: mem.Allocator, // TODO: this should be a pool
    exec_arena: mem.Dynamic_Arena,
    exec_allocator: mem.Allocator,
    exec_node_pool: MemoryPool(ExecTreeNode),
    user_data: rawptr,
    current_grammar: ^Parser,
}

handle_create :: proc() -> (pcl_handle: ^PCLHandle) {
    pcl_handle = new(PCLHandle)

    pcl_handle.rd = RecursionData{
        depth = 0,
        top_nodes = make(map[^Parser]ParseResult),
    }

    // allocator for the exec tree
    mem.dynamic_arena_init(&pcl_handle.tree_arena)
    pcl_handle.tree_allocator = mem.dynamic_arena_allocator(&pcl_handle.tree_arena)

    // allocator for the execution
    mem.dynamic_arena_init(&pcl_handle.exec_arena)
    pcl_handle.exec_allocator = mem.dynamic_arena_allocator(&pcl_handle.exec_arena)

    pcl_handle.exec_node_pool = memory_pool_create(ExecTreeNode, 0, pcl_handle.exec_allocator)
    return pcl_handle
}

handle_destroy :: proc(pcl_handle: ^PCLHandle) {
    delete(pcl_handle.rd.top_nodes)
    memory_pool_destroy_debug(&pcl_handle.exec_node_pool)
    mem.dynamic_arena_destroy(&pcl_handle.exec_arena)
    mem.dynamic_arena_destroy(&pcl_handle.tree_arena)
    free(pcl_handle)
}

handle_reset :: proc(pcl_handle: ^PCLHandle) {
    free_all(pcl_handle.tree_allocator)
    free_all(pcl_handle.exec_allocator)
    pcl_handle.exec_node_pool = memory_pool_create(ExecTreeNode, 0, pcl_handle.exec_allocator)
}

handle_grammar :: proc(pcl_handle: ^PCLHandle) -> ^Parser {
    return pcl_handle.current_grammar
}

// parse api ///////////////////////////////////////////////////////////////////

parse_string :: proc(
    pcl_handle: ^PCLHandle,
    parser: ^Parser,
    str: ^string,
    user_data: rawptr = nil,
) -> (state: ParserState, res: ExecResult, ok: bool) {
    // set the user data
    pcl_handle.user_data = user_data
    pcl_handle.current_grammar = parser

    // create the arena for the temporary allocations (error messages)
    bytes: [4096]u8
    error_arena: mem.Arena
    mem.arena_init(&error_arena, bytes[:])
    pcl_handle.error_allocator = mem.arena_allocator(&error_arena)
    defer pcl_handle.error_allocator = mem.Allocator{}

    // execute the given parser on the string and print error
    state = state_create(str, pcl_handle)
    parse_result, err := parser_parse(&state, parser)

    // make sure there are no trailing skipable runes
    parser_skip(&state, SKIP)

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
        case(^ExecTreeNode): res = exec_tree_exec(result, user_data,
                                                  pcl_handle.exec_allocator,
                                                  &pcl_handle.exec_node_pool)
        case(ExecResult): res = result
        }
    }
    return state, res, ok
}

// parse_string :: proc(
//     pcl_handle: ^PCLHandle,
//     parser: ^Parser,
//     str: string,
//     user_data: rawptr = nil,
// ) -> (state: ParserState, res: ExecResult, ok: bool) {
// }
