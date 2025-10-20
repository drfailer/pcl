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
        fmt.aprintf(str, ..args, allocator = state.error_allocator)
    }
}

// parser //////////////////////////////////////////////////////////////////////

ParseResult :: union {
    string,
    rawptr,
}

ExecProc :: proc(results: []ParseResult, exec_data: rawptr) -> ParseResult

PredProc :: proc(c: rune) -> bool

ParseProc :: proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError)

Parser :: struct {
    rc: u32, // TODO: parsers should be created using a dedicated arena so that they can be all freed at once
    name: string,
    parse: ParseProc,
    skip: PredProc,
    exec: ExecProc,
    pred: PredProc,
    parsers: [dynamic]^Parser,
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
    parser.rc = 0
    parser.name = name
    parser.parse = parse
    parser.skip = skip
    parser.exec = exec
    parser.pred = pred

    if parsers != nil && len(parsers) > 0 {
        parser.parsers = make([dynamic]^Parser, len(parsers))

        for sub_parser, idx in parsers {
            if sub_parser == nil do continue
            sub_parser.rc += 1
            parser.parsers[idx] = sub_parser
        }
    }
    return parser
}

parser_destroy :: proc(parser: ^Parser) {
    if parser.parsers != nil && len(parser.parsers) > 0 {
        for sub_parser in parser.parsers {
            sub_parser.rc -= 1
            if sub_parser.rc == 0 {
                parser_destroy(sub_parser)
            }
        }
    }
    delete(parser.parsers)
    free(parser)
}

parser_parse :: proc(state: ^ParserState, parser: ^Parser) -> (res: ParseResult, err: ParserError) {
    return parser->parse(state)
}

parser_skip_from_proc :: proc(state: ^ParserState, parser_skip: PredProc) {
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

parser_skip_from_parser :: proc(state: ^ParserState, parser: Parser) {
    parser_skip_from_proc(state, parser.skip)
}

parser_skip :: proc {
    parser_skip_from_parser,
    parser_skip_from_proc,
}

parser_exec_with_results :: proc(state: ^ParserState, exec: ExecProc, results: []ParseResult) -> ParseResult {
    if exec == nil {
        // FIXME: this is wrong
        // - incorect when len(results) > 0
        // - discard the tokens during recursion
        return results[0]
    }
    if state.rd.depth > 0 {
        if state.rd.current_node.ctx.exec != nil {
            node := new(ExecTree)
            node.lhs = state.rd.current_node
            state.rd.current_node = node
        }
        state.rd.current_node.ctx = ExecContext{exec, state^}
    } else {
        return exec(results, state.exec_data)
    }
    return nil
}

parser_exec_single_result :: proc(state: ^ParserState, exec: ExecProc, result: ParseResult) -> ParseResult {
    return parser_exec_with_results(state, exec, []ParseResult{result})
}

parser_exec_from_exec_tree :: proc(tree: ^ExecTree) -> ParseResult {
    if tree == nil {
        return nil
    }
    // defer free(tree)
    if tree.rhs == nil && tree.lhs == nil {
        return tree.ctx.exec([]ParseResult{state_string(&tree.ctx.state)}, tree.ctx.state.exec_data)
    }
    lhs_res := parser_exec_from_exec_tree(tree.lhs)
    rhs_res := parser_exec_from_exec_tree(tree.rhs)

    results := make([dynamic]ParseResult)
    defer delete(results)

    if lhs_res != nil do append(&results, lhs_res)
    if rhs_res != nil do append(&results, rhs_res)
    return tree.ctx.exec(results[:], tree.ctx.state.exec_data)
}

parser_exec :: proc {
    parser_exec_with_results,
    parser_exec_single_result,
}

// parse api ///////////////////////////////////////////////////////////////////

parse_string :: proc(
    parser: ^Parser,
    str: string,
    exec_data: rawptr = nil,
) -> (state: ParserState, res: ParseResult, ok: bool) {
    // create the arena for the temporary allocations (error messages)
    bytes: [4096]u8
    arena: mem.Arena
    mem.arena_init(&arena, bytes[:])

    // execute the given parser on the string and print error
    err: ParserError
    str := str
    state = state_create(&str, exec_data, mem.arena_allocator(&arena))
    res, err = parser_parse(&state, parser)

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
    }
    free_all(context.temp_allocator)
    return state, res, ok
}

// print grammar ///////////////////////////////////////////////////////////////

parser_print :: proc(parser: ^Parser) {
    // TODO
    // we need a combinator type in the parser
}
