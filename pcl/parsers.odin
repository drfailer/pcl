package pcl

import "core:fmt"

// characters and string literals //////////////////////////////////////////////

apply_predicate :: proc(
    self: ^Parser,
    state: ^ParserState,
    pred: proc(c: rune) -> bool,
    error: proc(parser: ^Parser, state: ^ParserState) -> ParserError,
) -> (res: ParseResult, err: ParserError) {
    parser_skip(state, self.skip)

    if state_eof(state) {
        return nil, error(self, state)
    }

    if pred(state_char(state)) {
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
    skip: SkipProc = SKIP,
    exec: ExecProc = nil,
    name: string = "one_of",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        return apply_predicate(
            self,
            state,
            proc(c: rune) -> bool {
                return strings.contains_rune(chars, rune(c))
            },
            proc(parser: ^Parser, state: ^ParserState) -> ParserError {
                return parser_error(SyntaxError, state, "{}: expected one of [{}]", parser.name, chars)
            },
        )
    }
    return parser_create(name, parse, skip, exec)
}

range :: proc(
    $c1: rune,
    $c2: rune,
    skip: SkipProc = SKIP,
    exec: ExecProc = nil,
    name: string = "range",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        return apply_predicate(
            self,
            state,
            proc(c: rune) -> bool {
                return c1 <= c && c <= c2
            },
            proc(parser: ^Parser, state: ^ParserState) -> ParserError {
                return parser_error(SyntaxError, state, "{}: expected range({}, {})", parser.name, c1, c2)
            },
        )
    }
    return parser_create(name, parse, skip, exec)
}

lit_c :: proc(
    char: rune,
    skip: SkipProc = SKIP,
    exec: ExecProc = nil,
    name: string = "lit_c",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        char := self.data.(rune)
        parser_skip(state, self.skip)

        if state_eof(state) {
            return nil, parser_error(SyntaxError, state, "{}: expected '{}', but eof was found.",
                                     self.name, char)
        }

        if (state_char(state) == char) {
            if ok := state_eat_one(state); !ok {
                return nil, InternalError{"state_eat_one failed."}
            }
            res = parser_exec(state, self.exec)
            state_save_pos(state)
            return res, nil
        }
        return nil, parser_error(SyntaxError, state, "{}: expected '{}', but {} was found.",
                                 self.name, char, state_char(state))
    }
    return parser_create(name, parse, skip, exec, data = char)
}

lit_str :: proc(
    str: string,
    skip: SkipProc = SKIP,
    exec: ExecProc = nil,
    name: string = "lit",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        str := self.data.(string)
        parser_skip(state, self.skip)
        for c in str {
            if state_eof(state) || state_char(state) != c {
                return nil, parser_error(SyntaxError, state, "expected literal `{}`", str)
            }
            if ok := state_eat_one(state); !ok {
                return nil, InternalError{"state_eat_one failed."}
            }
        }
        res = parser_exec(state, self.exec)
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, data = str)
}

lit :: proc { lit_c, lit_str }

// block ///////////////////////////////////////////////////////////////////////

// TODO: use the stack to add optional extra security
block_char :: proc(
    $opening: rune,
    $closing: rune,
    skip: SkipProc = SKIP,
    exec: ExecProc = nil,
    name: string = "block",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        parser_skip(state, self.skip)
        if state_char(state) != opening {
            return nil, parser_error(SyntaxError, state, "opening symbol not found in `{}({}, {})`.",
                                     self.name, opening, closing)
        }
        state_eat_one(state)
        char_stack: [dynamic]rune
        defer delete(char_stack)
        append(&char_stack, opening)

        begin_cur := state.cur
        end_cur := state.cur
        escaped := false

        for len(char_stack) > 0 {
            escaped = false
            if state_eof(state) {
                return nil, parser_error(SyntaxError, state,
                                         "closing symbol not found in `{}({}, {})`.",
                                         self.name, opening, closing)
            }
            if state_char(state) == '\\' {
                escaped = true
                state_eat_one(state)
                state_eat_one(state)
            }

            if state_char(state) == closing {
                if char_stack[len(char_stack) - 1] != closing {
                    return nil, parser_error(SyntaxError, state,
                                             "opening and closing simbol mismatch in `{}({}, {})`",
                                             self.name, opening, closing)
                }
                pop(&char_stack)
                end_cur = state.cur
            } else if state_char(state) == opening {
                append(&char_stack, closing)
            }
            state_eat_one(state)
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

block_str :: proc(
    $opening: string,
    $closing: string,
    skip: SkipProc = SKIP,
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

block :: proc {
    block_char,
    block_str,
}

// separated items list ////////////////////////////////////////////////////////

// TODO:
// - write a parser that takes a parser, a separator character and a bool (trailing coma authorized?)
// - parse the expression using the parser and run the execute function using only the productions of the given parser (without the commas and on one list)

separated_items :: proc(
    parser: ^Parser,
    $sep: rune,
    $allow_trailing_sep: bool,
    $allow_empty_list: bool,
    skip: SkipProc = SKIP,
    exec: ExecProc = nil,
    name: string = "separated_items",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult, allocator = state.global_state.tree_allocator)
        sub_state: ParserState
        trailing := false

        for {
            parser_skip(state, self.skip)
            sub_state = state^
            if res, err = parser_parse(&sub_state, self.parsers[0]); err != nil {
                break
            }
            state_set(state, &sub_state)
            append(&results, res)
            trailing = false

            parser_skip(state, self.skip)
            if state_char(state) != sep {
                break
            }
            state_eat_one(state)
            state_save_pos(state)
            trailing = true
        }

        if trailing && !allow_trailing_sep {
            return nil, parser_error(SyntaxError, state, "trailing character found in `{}({})`.",
                                     self.name, sep)
        }
        if len(results) == 0 && !allow_empty_list {
            return nil, parser_error(SyntaxError, state, "no items found in `{}({})`.",
                                     self.name, sep)
        }
        res = parser_exec(state, self.exec, results)
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

// numbers /////////////////////////////////////////////////////////////////////
