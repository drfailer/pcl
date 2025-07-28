package parodin

// default parser functions ////////////////////////////////////////////////////

default_parse :: proc(state: ParserState, parser: Parser) -> (new_state: ParserState, ok: bool) {
    return state, true
}

default_exec :: proc(content: string, user_data: rawptr) -> rawptr {
    return user_data
}

default_skip :: proc(c: u8) -> bool {
    return false
}

// combinators /////////////////////////////////////////////////////////////////

cond :: proc(
    pred: PredProc,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
) -> Parser {
    return PredParser {
        parse = proc(
            state: ParserState,
            ctx: PredParserContext
        ) -> (new_state: ParserState, ok: bool) {
            if state_eof(state) do return state, false

            new_state = parser_skip(state, ctx.skip)
            if (ctx.pred(state_char(new_state))) {
                new_state, ok = state_eat_one(state)
                if !ok do return state, false
                parser_exec(&new_state, ctx.exec)
                state_save_pos(&new_state)
                return new_state, true
            }
            return state, false
        },
        ctx = PredParserContext {
            skip = skip,
            exec = exec,
            pred = pred,
        },
    }
}

lit_c :: proc(
    $char: u8,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
) -> Parser {
    return cond(proc(c: u8) -> bool {
        return c == char
    }, skip, exec)
}

lit :: proc(
    $str: string,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
) -> Parser {
    return BasicParser {
        parse = proc(
            state: ParserState,
            ctx: BasicParserContext,
        ) -> (new_state: ParserState, ok: bool) {
            new_state = parser_skip(state, ctx.skip)
            for c in str {
                if state_eof(new_state) || state_char(new_state) != c {
                    return state, false
                }
            }
            parser_exec(&new_state, ctx.exec)
            state_save_pos(&new_state)
            return new_state, true
        },
        ctx = BasicParserContext {
            skip = skip,
            exec = exec,
        }
    }
}

one_of :: proc(
    $chars: string,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
) -> Parser {
    return cond(proc(c: u8) -> bool {
        return strings.contains_rune(chars, rune(c))
    }, skip, exec)
}

range :: proc(
    $c1: u8,
    $c2: u8,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
) -> Parser {
    return cond(proc(c: u8) -> bool {
        return c1 <= c && c <= c2
    }, skip, exec)
}

star :: proc(
    parser: Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
) -> Parser {
    parsers := make([dynamic]Parser, 1) // TODO: mem leak
    parsers[0] = parser

    return CombinatorParser {
        parse = proc(
            state: ParserState,
            ctx: CombinatorParserContext,
        ) -> (new_state: ParserState, ok: bool) {
            new_state = parser_skip(state, ctx.skip)
            sub_state := new_state
            for !state_eof(new_state) {
                sub_state = parser_parse(sub_state, ctx.parsers[0]) or_break
                new_state.cur = sub_state.cur
            }
            if new_state.cur > new_state.pos {
                parser_exec(&new_state, ctx.exec)
                state_save_pos(&new_state)
                return new_state, true
            }
            return state, true
        },
        ctx = CombinatorParserContext {
            skip = skip,
            exec = exec,
            parsers = parsers,
        }
    }
}

seq :: proc(
    parsers: ..Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec
) -> Parser {
    parsers_arr := make([dynamic]Parser, 0, len(parsers)) // TODO: mem leak

    for parser in parsers {
        append(&parsers_arr, parser)
    }
    return CombinatorParser {
        parse = proc(
            state: ParserState,
            ctx: CombinatorParserContext
        ) -> (new_state: ParserState, ok: bool) {
            new_state = parser_skip(state, ctx.skip)
            sub_state := new_state
            for parser in ctx.parsers {
                sub_state = parser_parse(sub_state, parser) or_return
                new_state.cur = sub_state.cur
            }
            parser_exec(&new_state, ctx.exec)
            state_save_pos(&new_state)
            return new_state, true
        },
        ctx = CombinatorParserContext {
            skip = skip,
            exec = exec,
            parsers = parsers_arr,
        }
    }
}
