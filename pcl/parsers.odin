package pcl

// characters and string literals //////////////////////////////////////////////

apply_predicate :: proc(
    self: ^Parser,
    state: ^ParserState,
    error: proc(parser: ^Parser, state: ^ParserState) -> ParserError,
) -> (res: ParseResult, err: ParserError) {
    pred := self.data.(PredProc)
    if state_eof(state) {
        return nil, error(self, state)
    }

    parser_skip(state, self.skip)
    if (pred(state_char(state))) {
        if ok := state_eat_one(state); !ok {
            return nil, InternalError{"state_eat_one failed."}
        }
        res = parser_exec(state, self.exec)
        state_save_pos(state)
        return res, nil
    }
    return nil, error(self, state)
}

one_of :: proc(
    $chars: string,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "one_of",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        return apply_predicate(self, state, proc(parser: ^Parser, state: ^ParserState) -> ParserError {
            return parser_error(SyntaxError, state, "{}: expected one of [{}]", parser.name, chars)
        })
    }
    return parser_create(name, parse, skip, exec, data = proc(c: rune) -> bool {
        return strings.contains_rune(chars, rune(c))
    })
}

range :: proc(
    $c1: rune,
    $c2: rune,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "range",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        return apply_predicate(self, state, proc(parser: ^Parser, state: ^ParserState) -> ParserError {
            return parser_error(SyntaxError, state, "{}: expected range({}, {})", parser.name, c1, c2)
        })
    }
    return parser_create(name, parse, skip, exec, data = proc(c: rune) -> bool {
        return c1 <= c && c <= c2
    })
}

lit_c :: proc(
    $char: rune,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "lit_c",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        return apply_predicate(self, state, proc(parser: ^Parser, state: ^ParserState) -> ParserError {
            return parser_error(SyntaxError, state, "{}: expected '{}'", parser.name, char)
        })
    }
    return parser_create(name, parse, skip, exec, data = proc(c: rune) -> bool {
        return c == char
    })
}

lit_str :: proc(
    $str: string,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "lit",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        parser_skip(state, self.skip)
        for c in str {
            if state_eof(state) || state_char(state) != c {
                return nil, SyntaxError{"expected literal `" + str + "`"}
            }
            if ok := state_eat_one(state); !ok {
                return nil, InternalError{"state_eat_one failed."}
            }
        }
        res = parser_exec(state, self.exec)
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec)
}

lit :: proc { lit_c, lit_str }

// block ///////////////////////////////////////////////////////////////////////

cursor_on_string :: proc(state: ^ParserState, $prefix: string) -> bool {
    state_idx := state.cur
    for c, idx in prefix {
        if state_idx > len(state.content) || state_char_at(state, state_idx) != c {
            return false
        }
        state_idx += 1
    }
    return true
}

block :: proc(
    $opening: string,
    $closing: string,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "block",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        parser_skip(state, self.skip)
        if !cursor_on_string(state, opening) {
            return nil, parser_error(SyntaxError, state, "opening string not found in `{}({}, {})`.",
                                     self.name, opening, closing)
        }
        state.cur += len(opening)
        state.loc.col += len(opening) // opening should not contain \n
        count := 1
        begin_cur := state.cur
        end_cur := state.cur

        for count > 0 {
            if state_eof(state) {
                return nil, parser_error(SyntaxError, state, "closing string not found in `{}({}, {})`.",
                                         self.name, opening, closing)
            }
            if cursor_on_string(state, closing) {
                count -= 1
                end_cur = state.cur
                state.cur += len(closing)
                state.loc.col += len(closing) // closing should not contain \n
            } else if cursor_on_string(state, opening) {
                count += 1
                state.cur += len(opening)
                state.loc.col += len(opening) // opening should not contain \n
            } else {
                state_eat_one(state)
            }
        }
        cur := state.cur
        state.pos = begin_cur
        state.cur = end_cur
        res = parser_exec(state, self.exec)
        state.cur = cur
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec)
}

// separated items list ////////////////////////////////////////////////////////

// TODO:
// - write a parser that takes a parser, a separator character and a bool (trailing coma authorized?)
// - parse the expression using the parser and run the execute function using only the productions of the given parser (without the commas and on one list)

// numbers /////////////////////////////////////////////////////////////////////
