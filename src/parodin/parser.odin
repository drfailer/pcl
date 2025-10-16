package parodin

import "core:strings"
import "core:fmt"
import "core:mem"

// parser //////////////////////////////////////////////////////////////////////

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

ParseResult :: union {
    string,
    rawptr,
}

// TODO:
// It would be better if the content could be the result of the sub rules (could it even be variadic?)
// ContentType :: union {string, rawptr}
// exec(r1, r2, ..., rn, exec_data)
// ExecProc :: proc(content: string, exec_data: rawptr)
ExecProc :: proc(results: []ParseResult, exec_data: rawptr) -> ParseResult

PredProc :: proc(c: rune) -> bool

ParseProc :: proc(self: ^Parser, state: ^ParserState) -> (err: ParserError)

Parser :: struct {
    rc: u32,
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

parser_parse :: proc(state: ^ParserState, parser: ^Parser) -> (err: ParserError) {
    return parser->parse(state)
}

parser_skip_from_proc :: proc(state: ^ParserState, parser_skip: PredProc) -> ^ParserState {
    state := state
    for state.cur < len(state.content) && parser_skip(state_char(state)) {
        state_advance(state) or_break
    }
    return state
}

parser_skip_from_parser :: proc(state: ^ParserState, parser: Parser) -> ^ParserState {
    return parser_skip_from_proc(state, parser.skip)
}

parser_skip :: proc {
    parser_skip_from_proc,
}

parser_exec_from_proc :: proc(state: ^ParserState, exec: ExecProc) {
    if exec == nil {
        state.parse_result = state_string(state)
        return
    }
    if state.rd.depth > 0 {
        append(&state.rd.current_node.execs, ExecContext{exec, state^})
    } else {
        state.parse_result = exec([]ParseResult{state_string(state)}, state.exec_data)
    }
}

parser_exec_from_parser :: proc(state: ^ParserState, parser: Parser) {
    parser_exec_from_proc(state, parser.exec)
}

parser_exec_from_exec_tree :: proc(tree: ^ExecTree) {
    if tree == nil {
        return
    }
    parser_exec_from_exec_tree(tree.rhs)
    parser_exec_from_exec_tree(tree.lhs)
    for &ctx in tree.execs {
        ctx.exec([]ParseResult{state_string(&ctx.state)}, ctx.state.exec_data)
    }
}

parser_exec :: proc {
    parser_exec_from_proc,
    parser_exec_from_parser,
}

// parse api ///////////////////////////////////////////////////////////////////

parse_string :: proc(
    parser: ^Parser,
    str: string,
    exec_data: rawptr = nil,
) -> (state: ParserState, ok: bool) {
    // create the arena for the temporary allocations (error messages)
    bytes: [4096]u8
    arena: mem.Arena
    mem.arena_init(&arena, bytes[:])
    context.temp_allocator = mem.arena_allocator(&arena)

    // execute the given parser on the string and print error
    str := str
    state = state_create(&str, exec_data)
    err := parser_parse(&state, parser)

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
    return state, ok
}

// print grammar ///////////////////////////////////////////////////////////////

parser_print :: proc(parser: ^Parser) {
    // TODO
    // we need a combinator type in the parser
}
