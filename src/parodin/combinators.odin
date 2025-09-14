package parodin

import "core:fmt"

// default parser functions ////////////////////////////////////////////////////

default_parse :: proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
    return state, true
}

default_exec :: proc(content: string, user_data: rawptr) -> rawptr {
    return user_data
}

test_exec :: proc($message: string) -> ExecProc {
    return proc(content: string, user_data: rawptr) -> rawptr {
        fmt.printfln("test_exec: {} (content = `{}')", message, content)
        return user_data
    }
}

default_skip :: proc(c: rune) -> bool {
    return false
}

// combinators /////////////////////////////////////////////////////////////////

// TODO: handle errors properly, the easiest way might be to extract logic into
//       extern function and test for the result (it will also make the code
//       more readable, convetion should be combinator_rule_parse +
//       combinator_rule functions, and the lambda print error messge if
//       required).

// TODO: should the skip function be recursive (so that it is only specified in
//       the top grammar)? -> if it is the case, it should not override skip
//       functions specified for the sub-rules.

declare :: proc(
    name: string = "",
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        if len(self.parsers) == 0 || self.parsers[0] == nil {
            fmt.printfln("error: unimplemented parser {}.", self.name)
            return state, false
        }
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        if sub_state, ok = parser_parse(sub_state, self.parsers[0]); !ok {
            return state, false
        }
        new_state.cur = sub_state.cur
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, true
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
    parser.parsers[0] = impl
}

empty :: proc(
    parser: ^Parser,
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        return state, true
    }
    return parser_create("emtpy", parse, default_skip, default_exec)
}

cond :: proc(
    pred: PredProc,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        if state_eof(state) do return state, false

            new_state = parser_skip(state, self.skip)
            if (self.pred(state_char(new_state))) {
                new_state, ok = state_eat_one(state)
                if !ok do return state, false
                    parser_exec(&new_state, self.exec)
                    state_save_pos(&new_state)
                    return new_state, true
            }
            return state, false
    }
    return parser_create(name, parse, skip, exec, pred = pred)
}

one_of :: proc(
    $chars: string,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    return cond(proc(c: rune) -> bool {
        return strings.contains_rune(chars, rune(c))
    }, skip, exec, name)
}

range :: proc(
    $c1: rune,
    $c2: rune,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    return cond(proc(c: rune) -> bool {
        return c1 <= c && c <= c2
    }, skip, exec, name)
}

lit_c :: proc(
    $char: rune,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    return cond(proc(c: rune) -> bool {
        return c == char
    }, skip, exec, name)
}

lit :: proc(
    $str: string,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        // TODO: clean up this function
        new_state = state
        sub_state := parser_skip(state, self.skip)
        for c in str {
            if state_eof(sub_state) || state_char(sub_state) != c {
                return state, false
            }
            sub_state = state_eat_one(sub_state) or_return
        }
        new_state = sub_state
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, true
    }
    return parser_create(name, parse, skip, exec)
}

single :: proc(
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        if sub_state, ok = parser_parse(sub_state, self.parsers[0]); !ok {
            return state, false
        }
        new_state.cur = sub_state.cur
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, true
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

star :: proc(
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        for !state_eof(new_state) {
            sub_state = parser_parse(sub_state, self.parsers[0]) or_break
            new_state.cur = sub_state.cur
        }
        if new_state.cur > new_state.pos {
            parser_exec(&new_state, self.exec)
            state_save_pos(&new_state)
            return new_state, true
        }
        return state, true
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

plus :: proc(
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        for !state_eof(new_state) {
            sub_state = parser_parse(sub_state, self.parsers[0]) or_break
            new_state.cur = sub_state.cur
        }
        if new_state.cur > new_state.pos {
            parser_exec(&new_state, self.exec)
            state_save_pos(&new_state)
            return new_state, true
        }
        return state, false
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

times :: proc(
    $nb_times: int,
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        count := 0
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        for !state_eof(new_state) && count < nb_times {
            sub_state = parser_parse(sub_state, self.parsers[0]) or_break
            new_state.cur = sub_state.cur
            count += 1
        }
        if count == nb_times {
            parser_exec(&new_state, self.exec)
            state_save_pos(&new_state)
            return new_state, true
        }
        return state, false
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

// TODO: is a while needed

seq :: proc(
    parsers: ..^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        new_state = state
        sub_state := new_state
        for parser in self.parsers {
            sub_state = parser_skip(sub_state, self.skip)
            if sub_state, ok = parser_parse(sub_state, parser); !ok {
                return state, false
            }
            new_state.cur = sub_state.cur
        }
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, true
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
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
    parsers: ..^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        new_state = parser_skip(state, self.skip)
        for parser in self.parsers {
            if end_state, ok := parser_parse(new_state, parser); ok {
                parser_exec(&end_state, self.exec)
                state_save_pos(&end_state)
                return end_state, true
            }
        }
        return state, false
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

opt :: proc(
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        if sub_state, ok = parser_parse(sub_state, self.parsers[0]); !ok {
            return state, true
        }
        new_state.cur = sub_state.cur
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, true
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
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "",
) -> ^Parser {
    // <expr> := <expr> "+" <term> | <term>
    //
    // <expr> := <term> <expr'>
    // <expr'> := "+" <term> <expr'> | empty
    //
    // <term> = <factor> <term'>
    // <term'> = "*" <factor> <term'> | emtpy
    //
    // <factor> = <number> | <parent>

    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, ok: bool) {
        run_exec := !new_state.defered_exec
        new_state = parser_skip(state, self.skip)
        new_state.defered_exec = true
        recursive_rule := self.parsers[0]
        terminal_rule := self.parsers[len(self.parsers) - 1]
        exec_list_len := len(state.exec_list)
        state := state

        state_print_context(state)
        fmt.printfln("terminal rule = {}", terminal_rule.name)

        // apply the terminal rule
        if new_state, ok = parser_parse(new_state, terminal_rule); !ok {
            remove_range(state.exec_list, exec_list_len, len(state.exec_list))
            return state, false
        }

        // if there are middle rules (like operators), this parser have to fail
        // if they are not found, otherwise, both exec functions of this parser
        // and the one of the terminal rule parser will be called. Note that
        // this behavior may change.
        new_state = parser_skip(new_state, self.skip)
        if  new_state.pos == len(new_state.content) {
            if len(self.parsers) > 2 {
                remove_range(state.exec_list, exec_list_len, len(state.exec_list))
                return state, false
            } else {
                return new_state, true
            }
        }

        for i := 1; i < len(self.parsers) - 1; i += 1 {
            if new_state, ok = parser_parse(new_state, self.parsers[i]); !ok {
                remove_range(state.exec_list, exec_list_len, len(state.exec_list))
                return state, false
            }
            new_state = parser_skip(new_state, self.skip)
        }
        if new_state, ok = parser_parse(new_state, recursive_rule); !ok {
            remove_range(state.exec_list, exec_list_len, len(state.exec_list))
            return state, false
        }

        if run_exec {
            #reverse for &exec_ctx in new_state.exec_list {
                exec_ctx.state.defered_exec = false
                parser_exec(&exec_ctx.state, exec_ctx.exec);
            }
            clear(new_state.exec_list)
            new_state.defered_exec = false
        }
        parser_exec(&new_state, self.exec)
        return new_state, true
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}
