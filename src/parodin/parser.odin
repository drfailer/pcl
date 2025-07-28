package parodin

import "core:strings"

// parser //////////////////////////////////////////////////////////////////////

ExecProc :: proc(content: string, user_data: rawptr) -> rawptr

PredProc :: proc(c: u8) -> bool

UserProcs :: struct {
    skip: PredProc,
    exec: ExecProc,
}

// basic parser

BasicParserContext :: struct {
    skip: PredProc,
    exec: ExecProc,
}

BasicParser :: struct {
    parse: proc(state: ParserState, ctx: BasicParserContext) -> (new_state: ParserState, ok: bool),
    ctx: BasicParserContext,
}

// predicate parser

PredParserContext :: struct {
    skip: PredProc,
    exec: ExecProc,
    pred: PredProc,
}

PredParser :: struct {
    parse: proc(state: ParserState, ctx: PredParserContext) -> (new_state: ParserState, ok: bool),
    ctx: PredParserContext,
}

// combinator parser

CombinatorParserContext :: struct {
    skip: PredProc,
    exec: ExecProc,
    parsers: [dynamic]Parser,
}

CombinatorParser :: struct {
    parse: proc(state: ParserState, ctx: CombinatorParserContext) -> (new_state: ParserState, ok: bool),
    ctx: CombinatorParserContext,
}

// parser

Parser :: union {
    BasicParser,
    PredParser,
    CombinatorParser,
}

parser_parse :: proc(state: ParserState, parser: Parser) -> (new_state: ParserState, ok: bool) {
    switch p in parser {
    case BasicParser: return p.parse(state, p.ctx)
    case PredParser: return p.parse(state, p.ctx)
    case CombinatorParser: return p.parse(state, p.ctx)
    }
    return
}

parser_skip_from_proc :: proc(state: ParserState, parser_skip: PredProc) -> ParserState {
    state := state
    for state.cur < len(state.content) && parser_skip(state_char(state)) {
        state.cur += 1
        state.pos += 1
    }
    return state
}

parser_skip_from_parser :: proc(state: ParserState, parser: Parser) -> ParserState {
    state := state
    switch p in parser {
    case BasicParser: return parser_skip_from_proc(state, p.ctx.skip)
    case PredParser: return parser_skip_from_proc(state, p.ctx.skip)
    case CombinatorParser: return parser_skip_from_proc(state, p.ctx.skip)
    }
    return state
}

parser_skip :: proc {
    parser_skip_from_proc,
    parser_exec_from_parser,
}

parser_exec_from_proc :: proc(state: ^ParserState, parser_exec: ExecProc) {
    state.user_data = parser_exec(state.content[state.pos:state.cur], state.user_data)
}

parser_exec_from_parser :: proc(state: ^ParserState, parser: Parser) {
    switch p in parser {
    case BasicParser: parser_exec_from_proc(state, p.ctx.exec)
    case PredParser: parser_exec_from_proc(state, p.ctx.exec)
    case CombinatorParser: parser_exec_from_proc(state, p.ctx.exec)
    }
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
