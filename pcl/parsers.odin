package pcl

// This file contains the built-in parsers. Note that those parser are meant to
// be simple, the complex sub-grammar parsers should be added in the grammar
// package.

import "core:fmt"
import "core:log"
import "core:strings"
import "core:unicode"

// characters and string literals //////////////////////////////////////////////

apply_predicate :: proc(
    self: ^Parser,
    state: ^ParserState,
    pred: proc(c: rune) -> bool,
) -> (status: ParserStatus) {
    cursors := parser_skip(state, self.skip)
    exec_len := parser_exec_list_len(state)

    if state_eof(state) {
        return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
    }

    if pred(state_char(state)) {
        state_eat_unsafe(state)
        return parser_parse_success(state, self.exec, cursors)
    }
    return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
}

PredicateParser :: struct {
    using parser: Parser,
    predicate: proc(c: rune) -> bool,
}

pred :: proc(
    pred: proc(c: rune) -> bool,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "pred",
) -> ^Parser {
    parse := proc(parser: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        self := cast(^PredicateParser)parser
        return apply_predicate(self, state, self.predicate)
    }
    parser := parser_create(PredicateParser, name, parse, skip, exec)
    parser.predicate = pred
    return parser
}

one_of :: proc(
    $chars: string,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "one_of",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        return apply_predicate(self, state, proc(c: rune) -> bool { return strings.contains_rune(chars, c) })
    }
    return parser_create(name, parse, skip, exec)
}

range :: proc(
    $c1: rune,
    $c2: rune,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "range",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        return apply_predicate(self, state, proc(c: rune) -> bool { return c1 <= c && c <= c2 })
    }
    return parser_create(name, parse, skip, exec)
}

rune_equal :: proc(lhs, rhs: rune, case_sensitive: bool) -> bool {
    if case_sensitive || !unicode.is_letter(lhs) {
        return lhs == rhs
    }
    lhs_upper := unicode.to_upper(lhs)
    rhs_upper := unicode.to_upper(rhs)
    return lhs_upper == rhs_upper
}

LitCParser :: struct {
    using parser: Parser,
    char: rune,
    case_sensitive: bool,
}

lit_c :: proc(
    char: rune,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "lit_c",
    case_sensitive := true,
) -> ^Parser {
    parse := proc(parser: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        self := cast(^LitCParser)parser
        char_str := transmute([size_of(rune)]u8)self.char
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        if state_eof(state) {
            return parser_parse_fail(state, cursors, exec_len, parser_failure(state, string(char_str[:])))
        }

        if rune_equal(state_char(state), self.char, self.case_sensitive) {
            state_eat_unsafe(state)
            return parser_parse_success(state, self.exec, cursors)
        }
        return parser_parse_fail(state, cursors, exec_len, parser_failure(state, string(char_str[:])))
    }
    parser := parser_create(LitCParser, name, parse, skip, exec)
    parser.char = char
    parser.case_sensitive = case_sensitive
    return parser
}

LitStrParser :: struct {
    using parser: Parser,
    str: string,
    case_sensitive: bool,
}

lit_str :: proc(
    str: string,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "lit",
    case_sensitive := true,
) -> ^Parser {
    parse := proc(parser: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        self := cast(^LitStrParser)parser
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        for c in self.str {
            if state_eof(state) || !rune_equal(state_char(state), c, self.case_sensitive) {
                return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.str))
            }
            state_eat_unsafe(state)
        }
        return parser_parse_success(state, self.exec, cursors)
    }
    parser := parser_create(LitStrParser, name, parse, skip, exec)
    parser.str = str
    parser.case_sensitive = case_sensitive
    return parser
}

lit :: proc { lit_c, lit_str }

// block ///////////////////////////////////////////////////////////////////////

/*
 * The block parers are used to create "half-parsers". They parse the opening
 * symbol, look for the closing one and return the text in between as a string.
 * This can be useful for writing a text-based preprocessor.
 */

/*
 * The char version of the block parser expects the bracket matching to be
 * correct, therefore, it will not raise any syntax error if brackets do not
 * match. This is done to allow ignoring wrapped closing symbols:
 *
 * c_code_block := block('{', '}')
 * content := `
 *     {
 *         printf("}"); // this closing bracket will be ignored
 *     }
 * `
 */
block_char :: proc(
    $opening: rune,
    $closing: rune,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "block",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)
        is_closing_map: map[rune]bool
        defer delete(is_closing_map)
        char_stack: [dynamic]rune
        defer delete(char_stack)

        if state_eof(state) || state_char(state) != opening {
            return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
        }
        state_eat_unsafe(state)
        append(&char_stack, closing)

        begin_cur := state.cursors.cur
        end_cur := state.cursors.cur
        escaped := false
        if opening == closing {
            is_closing_map[opening] = true
        }

        opening_char := opening
        closing_char := closing

        for len(char_stack) > 0 {
            escaped = false
            if state_eof(state) {
                return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
            }
            if state_char(state) == '\\' {
                escaped = true
                state_eat_non_eol_unsafe(state)
                state_eat_non_eol_unsafe(state)
                continue
            }
            if state_eof(state) {
                return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
            }

            switch state_char(state) {
            // we can image use one of these symbols to write strings in a
            // weird syntax, however, some of these may appear alone on
            // conventional syntaxes (especially '<' and '>'), therefore, we
            // will not test for these symbols
            // case '(', ')':
            //     opening_char = '('
            //     closing_char = ')'
            // case '{', '}':
            //     opening_char = '{'
            //     closing_char = '}'
            // case '[', ']':
            //     opening_char = '['
            //     closing_char = ']'
            // case '<', '>':
            //     opening_char = '<'
            //     closing_char = '>'
            case '"':
                opening_char = '"'
                closing_char = '"'
            case '\'':
                opening_char = '\''
                closing_char = '\''
            case:
                opening_char = opening
                closing_char = closing
            }

            closing_condition := state_char(state) == closing_char
            if closing_condition && opening_char == closing_char {
                closing_condition = is_closing_map[opening_char]
                is_closing_map[opening_char] = !is_closing_map[opening_char]
            }

            if closing_condition {
                if char_stack[len(char_stack) - 1] == closing_char {
                    pop(&char_stack)
                    end_cur = state.cursors.cur
                }
            } else if state_char(state) == opening_char {
                append(&char_stack, closing_char)
            }
            state_eat_unsafe(state)
        }
        return parser_parse_success(state, self.exec, cursors)
    }
    return parser_create(name, parse, skip, exec)
}

block_str :: proc(
    $opening: string,
    $closing: string,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "block",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        if !cursor_on_string(state, opening) {
            return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
        }
        state.cursors.cur += len(opening)
        state.cursors.loc.col += len(opening) // opening should not contain \n
        count := 1
        begin_cur := state.cursors.cur
        end_cur := state.cursors.cur

        for count > 0 {
            if state_eof(state) {
                return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
            }
            if cursor_on_string(state, closing) {
                count -= 1
                end_cur = state.cursors.cur
                state.cursors.cur += len(closing)
                state.cursors.loc.col += len(closing) // closing should not contain \n
            } else if cursor_on_string(state, opening) {
                count += 1
                state.cursors.cur += len(opening)
                state.cursors.loc.col += len(opening) // opening should not contain \n
            } else {
                state_eat_unsafe(state)
            }
        }
        return parser_parse_success(state, self.exec, cursors)
    }
    return parser_create(name, parse, skip, exec)
}

block :: proc {
    block_char,
    block_str,
}

// line stating with ///////////////////////////////////////////////////////////

line_starting_with :: proc(
    start_parser: CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "line_starting_with",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        if len(self.parsers) > 0 && self.parsers[0] != nil {
            state.global_state.handle.do_not_exec = true
            status = parser_parse(state, self.parsers[0])
            state.global_state.handle.do_not_exec = false
            if status != .Success {
                return parser_parse_fail(state, cursors, exec_len, status)
            }
        }

        // get the rest of the line
        for !state_eof(state) && state_char(state) != '\n' {
            state_eat_non_eol_unsafe(state)
        }
        state_eat(state) // eat the '\n' (does nothing if eof)

        return parser_parse_success(state, self.exec, cursors)
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, start_parser))
}

// separated items list ////////////////////////////////////////////////////////

SeparatedItemsParser :: struct {
    using parser: Parser,
    allow_trailing_separator: bool,
    allow_empty_list: bool,
    separator: rune,
}

separated_items :: proc(
    parser: ^Parser,
    separator: rune,
    allow_trailing_separator: bool = false,
    allow_empty_list: bool = true,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "separated_items",
) -> ^Parser {
    parse := proc(parser: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        self := cast(^SeparatedItemsParser)parser
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)
        trailing := false

        for {
            parser_skip(state, self.skip)
            if status = parser_parse(state, self.parsers[0]); status != .Success {
                break
            }
            trailing = false

            parser_skip(state, self.skip)
            if state_eof(state) || state_char(state) != self.separator {
                break
            }
            state_eat_non_eol_unsafe(state)
            trailing = true
        }

        if trailing && !self.allow_trailing_separator {
            return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
        }
        if state.cursors.cur == cursors.pos && !self.allow_empty_list {
            return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
        }
        return parser_parse_success(state, self.exec, cursors)
    }
    parser := parser_create(SeparatedItemsParser, name, parse, skip, exec, parsers = []^Parser{parser})
    parser.separator = separator
    parser.allow_trailing_separator = allow_trailing_separator
    parser.allow_empty_list = allow_empty_list
    return parser
}
