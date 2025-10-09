package parodin

import "core:fmt"
import "core:strings"

// default parser functions ////////////////////////////////////////////////////

default_exec :: proc(content: string, exec_data: rawptr) {}

test_exec :: proc($message: string) -> ExecProc {
    return proc(content: string, exec_data: rawptr) {
        fmt.printfln("test_exec: {} (content = `{}')", message, content)
    }
}

default_skip :: proc(c: rune) -> bool {
    return false
}

// combinators /////////////////////////////////////////////////////////////////

declare :: proc(
    name: string = "parser",
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        if len(self.parsers) == 0 || self.parsers[0] == nil {
            sb := strings.builder_make(allocator = context.temp_allocator)
            strings.write_string(&sb, "unimpleted parser `")
            strings.write_string(&sb, self.name)
            strings.write_string(&sb, "`.")
            return state, InternalError{strings.to_string(sb)}
        }

        // new_state = parser_skip(state, self.skip)
        // sub_state := new_state
        // if sub_state, err = parser_parse(sub_state, self.parsers[0]); err != nil {
        //     return sub_state, err
        // }
        // new_state.cur = sub_state.cur
        // parser_exec(&new_state, self.exec)
        // state_save_pos(&new_state)
        // return new_state, nil

        new_state = parser_skip(state, self.skip)
        if new_state, err = parser_parse(new_state, self.parsers[0]); err != nil {
            return new_state, err
        }
        return new_state, nil
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
    if parser.exec != default_exec && impl.exec == default_exec {
        impl.exec = parser.exec
    }
    parser.parsers[0] = impl
}

empty :: proc() -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        return state, nil
    }
    return parser_create("emtpy", parse, default_skip, default_exec)
}

// TODO: create a better error message for rules that use cond
cond :: proc(
    pred: PredProc,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "cond",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        ok: bool

        if state_eof(state) {
            return state, SyntaxError{"cannot apply predicated because eof was found."}
        }

        new_state = parser_skip(state, self.skip)
        if (self.pred(state_char(new_state))) {
            if new_state, ok = state_eat_one(new_state); !ok {
                return new_state, InternalError{"state_eat_one failed."}
            }
            parser_exec(&new_state, self.exec)
            state_save_pos(&new_state)
            return new_state, nil
        }
        return new_state, SyntaxError{"cannot apply predicate."}
    }
    return parser_create(name, parse, skip, exec, pred = pred)
}

one_of :: proc(
    $chars: string,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "one_of",
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
    name: string = "range",
) -> ^Parser {
    return cond(proc(c: rune) -> bool {
        return c1 <= c && c <= c2
    }, skip, exec, name)
}

lit_c :: proc(
    $char: rune,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "lit_c",
) -> ^Parser {
    return cond(proc(c: rune) -> bool {
        return c == char
    }, skip, exec, name)
}

lit :: proc(
    $str: string,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "lit",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        new_state := parser_skip(state, self.skip)
        for c in str {
            if state_eof(new_state) || state_char(new_state) != c {
                return new_state, SyntaxError{"expected literal `" + str + "`"}
            }
            new_state = state_eat_one(new_state) or_return
        }
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, nil
    }
    return parser_create(name, parse, skip, exec)
}

single :: proc(
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "single",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        if sub_state, err = parser_parse(sub_state, self.parsers[0]); err != nil {
            return sub_state, err
        }
        new_state.cur = sub_state.cur
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

star :: proc(
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "star",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        for !state_eof(new_state) {
            sub_state = parser_parse(sub_state, self.parsers[0]) or_break
            new_state.cur = sub_state.cur
        }
        if new_state.cur > new_state.pos {
            parser_exec(&new_state, self.exec)
            state_save_pos(&new_state)
            return new_state, nil
        }
        return state, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

plus :: proc(
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "plus",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        new_state = parser_skip(state, self.skip)
        sub_state := new_state
        for !state_eof(new_state) {
            sub_state = parser_parse(sub_state, self.parsers[0]) or_break
            new_state.cur = sub_state.cur
        }
        if new_state.cur > new_state.pos {
            parser_exec(&new_state, self.exec)
            state_save_pos(&new_state)
            return new_state, nil
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "rule {")
        strings.write_string(&sb, self.parsers[0].name)
        strings.write_string(&sb, "}+ failed.")
        return new_state, SyntaxError{strings.to_string(sb)}
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

times :: proc(
    $nb_times: int,
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "times",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
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
            return new_state, nil
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "rule {")
        strings.write_string(&sb, self.parsers[0].name)
        strings.write_string(&sb, "}{" + nb_times + "} failed (")
        strings.write_int(count)
        strings.write_string(&sb, " found).")
        return new_state, SyntaxError{strings.to_string(sb)}
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

seq :: proc(
    parsers: ..^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "seq",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        new_state = state
        sub_state := new_state
        for parser in self.parsers {
            sub_state = parser_skip(sub_state, self.skip)
            if sub_state, err = parser_parse(sub_state, parser); err != nil {
                switch e in err {
                case InternalError:
                    return sub_state, err
                case SyntaxError:
                    sb := strings.builder_make(allocator = context.temp_allocator)
                    strings.write_string(&sb, "parser `")
                    strings.write_string(&sb, parser.name)
                    strings.write_string(&sb, "` returned the error `")
                    strings.write_string(&sb, e.message)
                    strings.write_string(&sb, "` in sequece `")
                    strings.write_string(&sb, self.name)
                    strings.write_string(&sb, "`")
                    return sub_state, SyntaxError{strings.to_string(sb)}
                }
            }
            new_state.cur = sub_state.cur
        }
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, nil
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
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "or",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        new_state = parser_skip(state, self.skip)
        for parser in self.parsers {
            if sub_state, err := parser_parse(new_state, parser); err == nil {
                new_state.cur = sub_state.cur;
                parser_exec(&new_state, self.exec)
                state_save_pos(&new_state)
                return new_state, nil
            }
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "none of the rules in `")
        strings.write_string(&sb, self.name)
        strings.write_string(&sb, "`could be applied.")
        return new_state, SyntaxError{strings.to_string(sb)}
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

opt :: proc(
    parser: ^Parser,
    skip: PredProc = default_skip,
    exec: ExecProc = default_exec,
    name: string = "opt",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        new_state = parser_skip(state, self.skip)
        if new_state, err = parser_parse(new_state, self.parsers[0]); err != nil {
            return new_state, nil
        }
        parser_exec(&new_state, self.exec)
        state_save_pos(&new_state)
        return new_state, nil
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
    name: string = "lrec",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ParserState) -> (new_state: ParserState, err: ParserError) {
        recursive_rule := self.parsers[0]
        terminal_rule := self.parsers[len(self.parsers) - 1]
        middle_rules := self.parsers[1:len(self.parsers) - 1]

        run_exec := !state.defered_exec
        new_state = parser_skip(state, self.skip)
        new_state.defered_exec = true
        exec_list_len := len(state.exec_list)

        // apply the terminal rule
        if new_state, err = parser_parse(new_state, terminal_rule); err != nil {
            return new_state, err
        }

        new_state = parser_skip(new_state, self.skip)
        if  state_eof(new_state) && len(middle_rules) == 0 {
            return new_state, nil
        }

        // middle rules
        for parser in middle_rules {
            if new_state, err = parser_parse(new_state, parser); err != nil {
                remove_range(new_state.exec_list, exec_list_len, len(new_state.exec_list))
                return new_state, err
            }
            new_state = parser_skip(new_state, self.skip)
        }

        // recurse
        if new_state, err = parser_parse(new_state, recursive_rule); err != nil {
            remove_range(new_state.exec_list, exec_list_len, len(new_state.exec_list))
            return new_state, err
        }

        new_state.pos = state.pos
        inject_at(new_state.exec_list, exec_list_len, ExecContext{self.exec, new_state})
        if run_exec {
            #reverse for &ctx in new_state.exec_list {
                parser_exec(ctx);
            }
            clear(new_state.exec_list)
            new_state.defered_exec = false
        }
        return new_state, nil
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

// TODO: surround($open: rune, $close: rune)
