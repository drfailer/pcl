package parodin

import "core:fmt"
import "core:strings"
import "core:slice"

// default parser functions ////////////////////////////////////////////////////

test_exec :: proc($message: string) -> ExecProc {
    return proc(content: string, exec_data: rawptr) {
        fmt.printfln("test_exec: {} (content = `{}')", message, content)
    }
}

default_skip :: proc(c: rune) -> bool {
    return false
}

SKIP := default_skip

// combinators /////////////////////////////////////////////////////////////////

declare :: proc(
    name: string = "parser",
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        if len(self.parsers) == 0 || self.parsers[0] == nil {
            sb := strings.builder_make(allocator = context.temp_allocator)
            strings.write_string(&sb, "unimpleted parser `")
            strings.write_string(&sb, self.name)
            strings.write_string(&sb, "`.")
            return nil, InternalError{strings.to_string(sb)}
        }

        parser_skip(state, self.skip)
        if res, err = parser_parse(state, self.parsers[0]); err != nil {
            return nil, err
        }
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{nil})
}

define :: proc(parser: ^Parser, impl: ^Parser) {
    if len(parser.parsers) == 0 {
        fmt.printfln("error: cannot define parser {}.", parser.name)
    }
    if parser.parsers[0] != nil {
        fmt.printfln("error: redifinition of parser {}.", parser.name)
    }
    if parser.exec != nil && impl.exec == nil {
        impl.exec = parser.exec
    }
    parser.parsers[0] = impl
}

empty :: proc() -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        return nil, nil
    }
    return parser_create("emtpy", parse, SKIP, nil)
}

// TODO: create a better error message for rules that use cond
cond :: proc(
    pred: PredProc,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "cond",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        ok: bool

        if state_eof(state) {
            return nil, SyntaxError{"cannot apply predicated because eof was found."}
        }

        parser_skip(state, self.skip)
        if (self.pred(state_char(state))) {
            if ok = state_eat_one(state); !ok {
                return nil, InternalError{"state_eat_one failed."}
            }
            res = parser_exec(state, self.exec, state_string(state))
            state_save_pos(state)
            return res, nil
        }
        return nil, SyntaxError{"cannot apply predicate."}
    }
    return parser_create(name, parse, skip, exec, pred = pred)
}

one_of :: proc(
    $chars: string,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "one_of",
) -> ^Parser {
    return cond(proc(c: rune) -> bool {
        return strings.contains_rune(chars, rune(c))
    }, skip, exec, name)
}

range :: proc(
    $c1: rune,
    $c2: rune,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "range",
) -> ^Parser {
    return cond(proc(c: rune) -> bool {
        return c1 <= c && c <= c2
    }, skip, exec, name)
}

lit_c :: proc(
    $char: rune,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "lit_c",
) -> ^Parser {
    return cond(proc(c: rune) -> bool {
        return c == char
    }, skip, exec, name)
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
        res = parser_exec(state, self.exec, state_string(state))
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec)
}

lit :: proc { lit_c, lit_str }

// TODO regex rule

single :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "single",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        parser_skip(state, self.skip)
        sub_state := state^
        if res, err = parser_parse(&sub_state, self.parsers[0]); err != nil {
            return nil, err
        }
        state_set(state, &sub_state)
        res = parser_exec(state, self.exec, res)
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

star :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "star",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult)
        defer delete(results)

        parser_skip(state, self.skip)
        sub_state := state^
        for !state_eof(state) {
            sub_res := parser_parse(&sub_state, self.parsers[0]) or_break
            append(&results, sub_res)
            state_set(state, &sub_state)
        }
        if state.cur > state.pos {
            res = parser_exec(state, self.exec, results[:])
            state_save_pos(state)
            return res, nil
        }
        return nil, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

plus :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "plus",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult)
        defer delete(results)

        parser_skip(state, self.skip)
        sub_state := state^
        for !state_eof(state) {
            sub_res := parser_parse(&sub_state, self.parsers[0]) or_break
            append(&results, sub_res)
            state_set(state, &sub_state)
        }
        if state.cur > state.pos {
            res = parser_exec(state, self.exec, results[:])
            state_save_pos(state)
            return res, nil
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "rule {")
        strings.write_string(&sb, self.parsers[0].name)
        strings.write_string(&sb, "}+ failed.")
        return nil, SyntaxError{strings.to_string(sb)}
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

times :: proc(
    $nb_times: int,
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "times",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult)
        defer delete(results)
        count := 0

        parser_skip(state, self.skip)
        sub_state := state^
        for !state_eof(state) && count < nb_times {
            sub_res := parser_parse(&sub_state, self.parsers[0]) or_break
            append(&results, sub_res)
            state_set(state, &sub_state)
            count += 1
        }
        if count == nb_times {
            res = parser_exec(state, self.exec, results[:])
            state_save_pos(state)
            return res, nil
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "rule {")
        strings.write_string(&sb, self.parsers[0].name)
        strings.write_string(&sb, "}{" + nb_times + "} failed (")
        strings.write_int(count)
        strings.write_string(&sb, " found).")
        return nil, SyntaxError{strings.to_string(sb)}
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

seq :: proc(
    parsers: ..^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "seq",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult)
        defer delete(results)
        sub_state := state^
        sub_res: ParseResult

        for parser in self.parsers {
            parser_skip(&sub_state, self.skip)
            if sub_res, err = parser_parse(&sub_state, parser); err != nil {
                switch e in err {
                case InternalError:
                    return nil, err
                case SyntaxError:
                    sb := strings.builder_make(allocator = context.temp_allocator)
                    strings.write_string(&sb, "parser `")
                    strings.write_string(&sb, parser.name)
                    strings.write_string(&sb, "` returned the error `")
                    strings.write_string(&sb, e.message)
                    strings.write_string(&sb, "` in sequece `")
                    strings.write_string(&sb, self.name)
                    strings.write_string(&sb, "`")
                    return nil, SyntaxError{strings.to_string(sb)}
                }
            }
            append(&results, sub_res)
            state_set(state, &sub_state)
        }
        res = parser_exec(state, self.exec, results[:])
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

/*
 * The or process rules in order, which means that the first rule in the list
 * will be tested before the second. This parser is greedy and will return the
 * first rule that can be applied on the input.
 */
or :: proc(
    parsers: ..^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "or",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        parser_skip(state, self.skip)
        for parser in self.parsers {
            sub_state := state^
            if sub_res, sub_err := parser_parse(&sub_state, parser); sub_err == nil {
                state_set(state, &sub_state)
                res = parser_exec(state, self.exec, sub_res)
                state_save_pos(state)
                return res, nil
            }
            free_all(context.temp_allocator)
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "none of the rules in `")
        strings.write_string(&sb, self.name)
        strings.write_string(&sb, "`could be applied.")
        return nil, SyntaxError{strings.to_string(sb)}
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

opt :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "opt",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        parser_skip(state, self.skip)
        sub_state := state^
        if res, err = parser_parse(&sub_state, self.parsers[0]); err != nil {
            return nil, nil
        }
        free_all(context.temp_allocator)
        state_set(state, &sub_state)
        res = parser_exec(state, self.exec, res)
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

/*
 * Helper for left recursion.
 * Use:
 * <lrec_rule> := <recursive_rule> <op_rules> <terminal_rule> | <terminal_rule>
 * Transforms into:
 * <lrec_rule>  := <terminal_rule> <lrec_rule'>
 * <lrec_rule'> := <op_rules> <terminal_rule> <lrec_rule'> | empty if <op_rules> is empty
 *
 * <op_rules> are used to simplify the implementation of grammars
 * that include operators. If such rules are present, this parser will fail if
 * they cannot be applied. Otherwise, the parser will succeed if only the
 * <terminal_rule> is found.
 *
 * Example:
 * <expr> := <add> | <term>
 * <add>  := <expr> "+" <term>
 * => <add> := <term> <add'>
 *    <add'> := "+" <term> <add'>
 * With the current behavior, the <add> parser will fail if the "+" is not
 * found and only the exec function of <term> will be called.
 *
 */
lrec :: proc(
    parsers: ..^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "lrec",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        recursive_rule := self.parsers[0]
        terminal_rule := self.parsers[len(self.parsers) - 1]
        middle_rules := self.parsers[1:len(self.parsers) - 1]

        state.rd.current_node = new(ExecTree)

        state.rd.depth += 1

        // apply terminal rule
        parser_skip(state, self.skip)
        if _, err = parser_parse(state, terminal_rule); err != nil {
            return nil, err
        }

        if recursive_rule in state.rd.exec_trees {
            state.rd.exec_trees[recursive_rule].rhs = state.rd.current_node
            state.rd.exec_trees[recursive_rule].ctx.state.cur = state.pos
            state.rd.current_node = state.rd.exec_trees[recursive_rule]
        }

        // success if eof and no operator
        parser_skip(state, self.skip)
        if state_eof(state) && len(middle_rules) == 0 {
            delete_key(&state.rd.exec_trees, recursive_rule)
            return nil, nil
        }

        node := new(ExecTree)
        node.lhs = state.rd.current_node
        state.rd.current_node = node

        // apply middle rules
        for parser in middle_rules {
            if _, err = parser_parse(state, parser); err != nil {
                return nil, err
            }
            parser_skip(state, self.skip)
        }

        res = nil
        parser_exec(state, self.exec, res)
        node.ctx.state.pos = node.lhs.ctx.state.pos
        state.rd.exec_trees[recursive_rule] = node

        state.rd.current_node = new(ExecTree)

        // apply recursive rule
        if _, err = parser_parse(state, recursive_rule); err != nil {
            return nil, err
        }

        state.rd.depth -= 1
        if recursive_rule in state.rd.exec_trees {
            state.rd.current_node = state.rd.exec_trees[recursive_rule]
            delete_key(&state.rd.exec_trees, recursive_rule)
        }

        if state.rd.depth == 0 {
            // exec_tree_print(state.rd.current_node)
            res = parser_exec_from_exec_tree(state.rd.current_node)
            state.rd.current_node = nil
            clear(&state.rd.exec_trees)
        }
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

rec :: proc(parser: ^Parser) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        recursive_rule := self.parsers[0]

        rd := state.rd
        state.rd.exec_trees = map[^Parser]^ExecTree{}

        if res, err = parser_parse(state, self.parsers[0]); err != nil {
            return nil, err
        }

        if recursive_rule in rd.exec_trees {
            // do not reset the rhs here!
            // rd.exec_trees[recursive_rule].rhs = state.rd.current_node
            state.rd.exec_trees[recursive_rule] = rd.exec_trees[recursive_rule]
        }

        return res, nil
    }
    return parser_create("", parse, nil, nil, parsers = []^Parser{parser})
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
        if !state_cursor_on_string(state, opening) {
            return SyntaxError{"execpted `" + opening + "`"}
        }
        state.cur += len(opening)
        count := 1

        for count > 0 {
            if state_eof(state) {
                return SyntaxError{"failed to parse `block " + opening + " ... " + closing + "`"}
            }
            if !state_cursor_on_string(state, opening) {
                count += 1
                state.cur += len(opening)
            } else if !state_cursor_on_string(state, closing) {
                count -= 1
            } else {
                state.cur += len(closing)
            }
        }
        res = parser_exec(state, self.exec)
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec)
}
