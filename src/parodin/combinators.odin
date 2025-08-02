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

// TODO: handle errors properly, the easiest way might be to extract logic into
//       extern function and test for the result (it will also make the code
//       more readable, convetion should be combinator_rule_parse +
//       combinator_rule functions, and the lambda print error messge if
//       required).

cond :: proc(
    pred: PredProc,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext,
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
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
            pred = pred,
        },
    }
}

one_of :: proc(
    $chars: string,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    return cond(proc(c: u8) -> bool {
        return strings.contains_rune(chars, rune(c))
    }, skip, exec, name)
}

range :: proc(
    $c1: u8,
    $c2: u8,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    return cond(proc(c: u8) -> bool {
        return c1 <= c && c <= c2
    }, skip, exec, name)
}

lit_c :: proc(
    $char: u8,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    return cond(proc(c: u8) -> bool {
        return c == char
    }, skip, exec, name)
}

lit :: proc(
    $str: string,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext,
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
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
        }
    }
}

single :: proc(
    parser: Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    parsers := make([dynamic]Parser, 1) // TODO: mem leak
    parsers[0] = parser

    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext,
        ) -> (new_state: ParserState, ok: bool) {
            new_state = parser_skip(state, ctx.skip)
            sub_state := new_state
            if sub_state, ok = parser_parse(sub_state, ctx.parsers[0]); !ok {
                return state, false
            }
            new_state.cur = sub_state.cur
            parser_exec(&new_state, ctx.exec)
            state_save_pos(&new_state)
            return new_state, true
        },
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
            parsers = parsers,
        }
    }
}

star :: proc(
    parser: Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    parsers := make([dynamic]Parser, 1) // TODO: mem leak
    parsers[0] = parser

    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext,
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
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
            parsers = parsers,
        }
    }
}

plus :: proc(
    parser: Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    parsers := make([dynamic]Parser, 1) // TODO: mem leak
    parsers[0] = parser

    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext,
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
            return state, false
        },
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
            parsers = parsers,
        }
    }
}

times :: proc(
    $nb_times: int,
    parser: Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    parsers := make([dynamic]Parser, 1) // TODO: mem leak
    parsers[0] = parser

    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext,
        ) -> (new_state: ParserState, ok: bool) {
            count := 0
            new_state = parser_skip(state, ctx.skip)
            sub_state := new_state
            for !state_eof(new_state) && count < nb_times {
                sub_state = parser_parse(sub_state, ctx.parsers[0]) or_break
                new_state.cur = sub_state.cur
                count += 1
            }
            if count == nb_times {
                parser_exec(&new_state, ctx.exec)
                state_save_pos(&new_state)
                return new_state, true
            }
            return state, false
        },
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
            parsers = parsers,
        }
    }
}

// TODO: is a while needed

seq :: proc(
    parsers: ..Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    parsers_arr := make([dynamic]Parser, 0, len(parsers)) // TODO: mem leak

    for parser in parsers {
        append(&parsers_arr, parser)
    }
    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext
        ) -> (new_state: ParserState, ok: bool) {
            new_state = parser_skip(state, ctx.skip)
            sub_state := new_state
            for parser in ctx.parsers {
                if sub_state, ok = parser_parse(sub_state, parser); !ok {
                    return state, false
                }
                new_state.cur = sub_state.cur
            }
            parser_exec(&new_state, ctx.exec)
            state_save_pos(&new_state)
            return new_state, true
        },
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
            parsers = parsers_arr,
        }
    }
}

// TODO: we should have a rule that always try to parse the longuest string.
// longuest string. Later, we could have an expect or validate rule that allow
// to optimize this (branch rule?

/*
 * The or process rules in order, which means that the first rule in the list
 * will be tested before the second. This parser is greedy and will return the
 * first rule that can be applied on the input.
 */
or :: proc(
    parsers: ..Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    parsers_arr := make([dynamic]Parser, 0, len(parsers)) // TODO: mem leak

    for parser in parsers {
        append(&parsers_arr, parser)
    }
    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext
        ) -> (new_state: ParserState, ok: bool) {
            new_state = parser_skip(state, ctx.skip)
            for parser in ctx.parsers {
                if end_state, ok := parser_parse(new_state, parser); ok {
                    parser_exec(&end_state, ctx.exec)
                    state_save_pos(&end_state)
                    return end_state, true
                }
            }
            return state, false
        },
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
            parsers = parsers_arr,
        }
    }
}

opt :: proc(
    parser: Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> Parser {
    parsers := make([dynamic]Parser, 1) // TODO: mem leak
    parsers[0] = parser

    return Parser {
        parse = proc(
            state: ParserState,
            ctx: ParserContext,
        ) -> (new_state: ParserState, ok: bool) {
            new_state = parser_skip(state, ctx.skip)
            sub_state := new_state
            if sub_state, ok = parser_parse(sub_state, ctx.parsers[0]); !ok {
                return state, true
            }
            new_state.cur = sub_state.cur
            parser_exec(&new_state, ctx.exec)
            state_save_pos(&new_state)
            return new_state, true
        },
        ctx = ParserContext {
            name = name,
            skip = skip,
            exec = exec,
            parsers = parsers,
        }
    }
}

// TODO: rec, right_rec, left_rec
