package pcl

import "core:strings"
import "core:fmt"
import "core:mem"

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

// parser //////////////////////////////////////////////////////////////////////

ExecResult :: union {
    string,              // sub-string of the state
    rawptr,              // user pointer
    [dynamic]ExecResult, // multiple results
}

ParseResult :: ^ExecTreeNode

ExecProc :: proc(results: []ExecResult, exec_data: rawptr) -> ExecResult

PredProc :: proc(c: rune) -> bool

ParseProc :: proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError)

Parser :: struct {
    name: string,
    parse: ParseProc,
    skip: PredProc,
    exec: ExecProc,
    pred: PredProc,
    parsers: [dynamic]^Parser,
}

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

parser_create :: proc(
    name: string,
    parse: ParseProc,
    skip: PredProc,
    exec: ExecProc,
    pred: PredProc = nil,
    parsers: []^Parser = nil,
) -> ^Parser {
    parser := new(Parser)
    parser.name = name
    parser.parse = parse
    parser.skip = skip
    parser.exec = exec
    parser.pred = pred

    if parsers != nil && len(parsers) > 0 {
        parser.parsers = make([dynamic]^Parser, len(parsers))

        for sub_parser, idx in parsers {
            if sub_parser == nil do continue
            parser.parsers[idx] = sub_parser
        }
    }
    return parser
}

// parse api ///////////////////////////////////////////////////////////////////

parse_string :: proc(
    parser: ^Parser,
    str: string,
    exec_data: rawptr = nil,
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

    // execute the given parser on the string and print error
    str := str
    global_state := GlobalParserState{
        exec_data = exec_data,
        rd = RecursionData{
            depth = 0,
            top_nodes = make(map[^Parser]^ExecTreeNode),
        },
        error_allocator = error_allocator,
        tree_allocator = tree_allocator,
    }
    defer delete(global_state.rd.top_nodes)
    state = state_create(&str, &global_state)
    defer state_destroy(&state)
    exec_tree, err := parser_parse(&state, parser)

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
        // allocator for the exec tree
        exec_arena: mem.Dynamic_Arena
        mem.dynamic_arena_init(&exec_arena)
        defer mem.dynamic_arena_destroy(&exec_arena)

        res = exec_tree_node_execute(exec_tree, mem.dynamic_arena_allocator(&exec_arena))
        exec_tree_node_destroy(exec_tree)
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

parser_skip :: proc(state: ^ParserState, parser_skip: PredProc) {
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

// exec tree functions /////////////////////////////////////////////////////////

parser_exec_with_childs :: proc(state: ^ParserState, exec: ExecProc, childs: [dynamic]ParseResult) -> ParseResult {
    node := new(ExecTreeNode, state.global_state.tree_allocator)
    // node := new(ExecTreeNode)
    node.ctx = ExecContext{exec, state^}
    node.childs = childs
    return node
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
