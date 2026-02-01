package pcl

import "core:strings"
import "core:fmt"
import "core:mem"

// parser //////////////////////////////////////////////////////////////////////

Parser :: struct {
    name: string,
    parse: ParseProc,
    skip: SkipProc, // skip proc
    exec: ExecProc,
    data: ParserData,
    parsers: [dynamic]^Parser,
}

ParserData :: union {
    string,
    rune,
    rawptr,
}

// ParseResult :: ^ExecTreeNode

ParseResult :: union {
    ^ExecTreeNode,
    ExecResult,
}


SkipProc :: proc(c: rune) -> bool // TODO: should it take the state?

ParseProc :: proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError)

ParserAllocator :: mem.Allocator

parser_allocator_create :: proc() -> ParserAllocator {
    arena := new(mem.Dynamic_Arena)
    mem.dynamic_arena_init(arena)
    return mem.dynamic_arena_allocator(arena)
}

parser_allocator_destroy :: proc(allocator: ParserAllocator) {
    arena := cast(^mem.Dynamic_Arena)allocator.data
    mem.dynamic_arena_destroy(arena)
    free(arena)
}

parser_create_from_dynamic_array :: proc(
    name: string,
    parse: ParseProc,
    skip: SkipProc,
    exec: ExecProc,
    data: ParserData,
    parsers: [dynamic]^Parser,
) -> ^Parser {
    parser := new(Parser)
    parser.name = name
    parser.parse = parse
    parser.skip = skip
    parser.exec = exec
    parser.data = data
    parser.parsers = parsers
    return parser
}

parser_create_from_slice :: proc(
    name: string,
    parse: ParseProc,
    skip: SkipProc,
    exec: ExecProc,
    data: ParserData = nil,
    parsers: []^Parser = nil,
) -> ^Parser {
    parser_array: [dynamic]^Parser
    if parsers != nil && len(parsers) > 0 {
        parser_array = make([dynamic]^Parser, len(parsers))

        for sub_parser, idx in parsers {
            if sub_parser == nil do continue
            parser_array[idx] = sub_parser
        }
    }
    return parser_create_from_dynamic_array(name, parse, skip, exec, data, parser_array)
}

parser_create :: proc {
    parser_create_from_dynamic_array,
    parser_create_from_slice,
}

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

// print grammar ///////////////////////////////////////////////////////////////

parser_print :: proc(parser: ^Parser) {
    // TODO
    // we need a combinator type in the parser
}

// helper functions ////////////////////////////////////////////////////////////

parser_parse :: proc(state: ^ParserState, parser: ^Parser) -> (res: ParseResult, err: ParserError) {
    return parser->parse(state)
}

parser_skip :: proc(state: ^ParserState, parser_skip: SkipProc) {
    if parser_skip == nil {
        return
    }
    state := state
    for state.cur < len(state.content) && parser_skip(state_char(state)) {
        if state_char(state) == '\n' {
            state.loc.row += 1
            state.loc.col = 1
        }
        state_advance(state)
    }
}

// errors //////////////////////////////////////////////////////////////////////

SyntaxError :: struct {
    message: string,
}

InternalError :: struct {
    message: string,
}

ParserError :: union {
    SyntaxError,
    InternalError,
}

parser_error :: proc($error_type: typeid, state: ^ParserState, str: string, args: ..any) -> ParserError {
    return error_type{
        fmt.aprintf(str, ..args, allocator = state.global_state.error_allocator)
    }
}

// exec tree functions /////////////////////////////////////////////////////////

parser_exec_with_childs :: proc(state: ^ParserState, exec: ExecProc, childs: [dynamic]ParseResult) -> ParseResult {
    pr: ParseResult

    // fmt.printfln("rec depth = {}, branch depth = {}", state.global_state.rd.depth, state.global_state.branch_depth)
    if state.global_state.rd.depth == 0 && state.global_state.branch_depth == 0 {
        if len(childs) == 0 {
            if exec == nil {
                pr = cast(ExecResult)state_string(state)
            } else {
                pr = exec(&ExecData{
                    content = []ExecResult{cast(ExecResult)state_string(state)},
                    user_data = state.global_state.user_data,
                    allocator = state.global_state.exec_allocator,
                })
            }
        } else {
            childs_results := make([dynamic]ExecResult, allocator = state.global_state.exec_allocator)

            for child in childs {
                switch c in child {
                case (^ExecTreeNode):
                    if child != nil {
                        append(&childs_results, exec_tree_exec(
                                      c,
                                      state.global_state.user_data,
                                      state.global_state.exec_allocator,
                                      &state.global_state.exec_node_pool,
                                      ))
                    }
                case (ExecResult):
                    append(&childs_results, c)
                }
            }

            if exec == nil {
                if len(childs_results) == 1 {
                    pr = childs_results[0]
                    delete(childs_results)
                } else {
                    pr = cast(ExecResult)childs_results
                }
            } else {
                pr = exec(&ExecData{
                    content = childs_results[:],
                    user_data = state.global_state.user_data,
                    allocator = state.global_state.exec_allocator,
                })
                delete(childs_results)
            }
        }
    } else {
        pr = memory_pool_allocate(&state.global_state.exec_node_pool)
        pr.(^ExecTreeNode).ctx = ExecContext{exec, state^}
        pr.(^ExecTreeNode).childs = childs
    }
    return pr
}

parser_exec_with_child :: proc(state: ^ParserState, exec: ExecProc, result: ParseResult) -> ParseResult {
    results := make([dynamic]ParseResult, allocator = state.global_state.tree_allocator)
    append(&results, result)
    return parser_exec_with_childs(state, exec, results)
}

parser_exec_no_child :: proc(state: ^ParserState, exec: ExecProc) -> ParseResult {
    return parser_exec_with_childs(state, exec, [dynamic]ParseResult{})
}

parser_exec :: proc {
    parser_exec_with_childs,
    parser_exec_with_child,
    parser_exec_no_child,
}
