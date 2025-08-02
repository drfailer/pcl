package parodin

import "core:strings"

// parser //////////////////////////////////////////////////////////////////////

ExecProc :: proc(content: string, user_data: rawptr) -> rawptr

PredProc :: proc(c: u8) -> bool

ParserContext :: struct {
    rc: u32,
    name: string,
    skip: PredProc,
    exec: ExecProc,
    pred: PredProc,
    parsers: [dynamic]Parser, // TODO: use a pointer
}

Parser :: struct {
    parse: proc(state: ParserState, ctx: ParserContext) -> (new_state: ParserState, ok: bool),
    ctx: ParserContext,
}

parser_parse :: proc(state: ParserState, parser: Parser) -> (new_state: ParserState, ok: bool) {
    return parser.parse(state, parser.ctx)
}

parser_skip_from_proc :: proc(state: ParserState, parser_skip: PredProc) -> ParserState {
    state := state
    for state.cur < len(state.content) && parser_skip(state_char(state)) {
        // TODO: use a function in state that will properly do the update (will be useful to count lines, ...)
        state.cur += 1
        state.pos += 1
    }
    return state
}

parser_skip_from_parser :: proc(state: ParserState, parser: Parser) -> ParserState {
    return parser_skip_from_proc(state, parser.ctx.skip)
}

parser_skip :: proc {
    parser_skip_from_proc,
    parser_exec_from_parser,
}

parser_exec_from_proc :: proc(state: ^ParserState, parser_exec: ExecProc) {
    state.user_data = parser_exec(state.content[state.pos:state.cur], state.user_data)
}

parser_exec_from_parser :: proc(state: ^ParserState, parser: Parser) {
    parser_exec_from_proc(state, parser.ctx.exec)
}

parser_exec :: proc {
    parser_exec_from_proc,
    parser_exec_from_parser,
}

// parse api ///////////////////////////////////////////////////////////////////

parse_string :: proc(
    parser: Parser,
    str: string,
    user_data: rawptr = nil,
) -> (new_state: ParserState, ok: bool) {
    str := str
    return parser_parse(ParserState{&str, 0, 0, user_data}, parser)
}
