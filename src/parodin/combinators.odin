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

// default parser functions ////////////////////////////////////////////////////

SKIP := default_skip

// combinators /////////////////////////////////////////////////////////////////

declare :: proc(
    name: string = "parser",
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        if len(self.parsers) == 0 || self.parsers[0] == nil {
            sb := strings.builder_make(allocator = context.temp_allocator)
            strings.write_string(&sb, "unimpleted parser `")
            strings.write_string(&sb, self.name)
            strings.write_string(&sb, "`.")
            return InternalError{strings.to_string(sb)}
        }

        parser_skip(state, self.skip)
        if err = parser_parse(state, self.parsers[0]); err != nil {
            return err
        }
        return nil
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

// Hack to reset the context when using left recursion
define_rec :: proc(parser: ^Parser, impl: ^Parser) {
    define(parser, rec_impl(parser, impl))
}

empty :: proc() -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        return nil
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        ok: bool

        if state_eof(state) {
            return SyntaxError{"cannot apply predicated because eof was found."}
        }

        parser_skip(state, self.skip)
        if (self.pred(state_char(state))) {
            if ok = state_eat_one(state); !ok {
                return InternalError{"state_eat_one failed."}
            }
            parser_exec(state, self.exec)
            state_save_pos(state)
            return nil
        }
        return SyntaxError{"cannot apply predicate."}
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        parser_skip(state, self.skip)
        for c in str {
            if state_eof(state) || state_char(state) != c {
                return SyntaxError{"expected literal `" + str + "`"}
            }
            if ok := state_eat_one(state); !ok {
                return InternalError{"state_eat_one failed."}
            }
        }
        parser_exec(state, self.exec)
        state_save_pos(state)
        return nil
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        parser_skip(state, self.skip)
        sub_state := state^
        if err = parser_parse(&sub_state, self.parsers[0]); err != nil {
            return err
        }
        state_set(state, &sub_state)
        parser_exec(state, self.exec)
        state_save_pos(state)
        return nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

star :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "star",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        parser_skip(state, self.skip)
        sub_state := state^
        for !state_eof(state) {
            parser_parse(&sub_state, self.parsers[0]) or_break
            state_set(state, &sub_state)
        }
        if state.cur > state.pos {
            parser_exec(state, self.exec)
            state_save_pos(state)
            return nil
        }
        return nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

plus :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "plus",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        parser_skip(state, self.skip)
        sub_state := state^
        for !state_eof(state) {
            parser_parse(&sub_state, self.parsers[0]) or_break
            state_set(state, &sub_state)
        }
        if state.cur > state.pos {
            parser_exec(state, self.exec)
            state_save_pos(state)
            return nil
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "rule {")
        strings.write_string(&sb, self.parsers[0].name)
        strings.write_string(&sb, "}+ failed.")
        return SyntaxError{strings.to_string(sb)}
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        count := 0
        parser_skip(state, self.skip)
        sub_state := state^
        for !state_eof(state) && count < nb_times {
            parser_parse(&sub_state, self.parsers[0]) or_break
            state_set(state, &sub_state)
            count += 1
        }
        if count == nb_times {
            parser_exec(state, self.exec)
            state_save_pos(state)
            return nil
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "rule {")
        strings.write_string(&sb, self.parsers[0].name)
        strings.write_string(&sb, "}{" + nb_times + "} failed (")
        strings.write_int(count)
        strings.write_string(&sb, " found).")
        return SyntaxError{strings.to_string(sb)}
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

seq :: proc(
    parsers: ..^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "seq",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        sub_state := state^
        for parser in self.parsers {
            parser_skip(&sub_state, self.skip)
            if err = parser_parse(&sub_state, parser); err != nil {
                switch e in err {
                case InternalError:
                    return err
                case SyntaxError:
                    sb := strings.builder_make(allocator = context.temp_allocator)
                    strings.write_string(&sb, "parser `")
                    strings.write_string(&sb, parser.name)
                    strings.write_string(&sb, "` returned the error `")
                    strings.write_string(&sb, e.message)
                    strings.write_string(&sb, "` in sequece `")
                    strings.write_string(&sb, self.name)
                    strings.write_string(&sb, "`")
                    return SyntaxError{strings.to_string(sb)}
                }
            }
            state_set(state, &sub_state)
        }
        parser_exec(state, self.exec)
        state_save_pos(state)
        return nil
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        parser_skip(state, self.skip)
        for parser in self.parsers {
            sub_state := state^
            if err := parser_parse(&sub_state, parser); err == nil {
                state_set(state, &sub_state)
                parser_exec(state, self.exec)
                state_save_pos(state)
                return nil
            }
            free_all(context.temp_allocator)
        }
        sb := strings.builder_make(allocator = context.temp_allocator)
        strings.write_string(&sb, "none of the rules in `")
        strings.write_string(&sb, self.name)
        strings.write_string(&sb, "`could be applied.")
        return SyntaxError{strings.to_string(sb)}
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

opt :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "opt",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        parser_skip(state, self.skip)
        sub_state := state^
        if err = parser_parse(&sub_state, self.parsers[0]); err != nil {
            return nil
        }
        free_all(context.temp_allocator)
        state_set(state, &sub_state)
        parser_exec(state, self.exec)
        state_save_pos(state)
        return nil
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
    // TODO: abort if the recursive rules wasn't defined with define_rec
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        recursive_rule := self.parsers[0]
        terminal_rule := self.parsers[len(self.parsers) - 1]
        middle_rules := self.parsers[1:len(self.parsers) - 1]

        // TODO: allocating here avoids having extra exec in the list. clearing
        //       doesn't work for a mysterious reason...
        state.rd.current_node = new(ExecTree)
        // clear(&state.rd.current_node.execs)

        state.rd.depth += 1

        // apply terminal rule
        parser_skip(state, self.skip)
        if err = parser_parse(state, terminal_rule); err != nil {
            return err
        }

        // success if eof and no operator
        parser_skip(state, self.skip)
        if state_eof(state) && len(middle_rules) == 0 {
            return nil
        }

        // prepare the new node
        node := new(ExecTree)
        node.lhs = state.rd.current_node
        state.rd.current_node = node

        // apply middle rules
        for parser in middle_rules {
            if err = parser_parse(state, parser); err != nil {
                return err
            }
            parser_skip(state, self.skip)
        }

        parser_exec(state, self.exec)
        state.rd.exec_trees[recursive_rule] = node

        // apply recursive rule
        if err = parser_parse(state, recursive_rule); err != nil {
            return err
        }

        state.rd.depth -= 1
        if recursive_rule in state.rd.exec_trees {
            state.rd.current_node = state.rd.exec_trees[recursive_rule]
        }

        if state.rd.depth == 0 {
            fmt.println("exec tree:")
            exec_tree_exec(state.rd.current_node)
            state.rd.current_node = nil
            clear(&state.rd.exec_trees)
        }
        return nil
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

@(private="file")
rec_impl :: proc(parser: ^Parser, impl: ^Parser) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        recursive_rule := self.parsers[0]
        impl := self.parsers[1]

        node := new(ExecTree)
        rd := state.rd
        state.rd.exec_trees = map[^Parser]^ExecTree{}
        state.rd.current_node = node

        if err = parser_parse(state, impl); err != nil {
            free(node)
            return err
        }

        if recursive_rule in rd.exec_trees {
            rd.exec_trees[recursive_rule].rhs = state.rd.current_node
            state.rd.exec_trees[recursive_rule] = rd.exec_trees[recursive_rule]
        }

        return nil
    }
    return parser_create("rec_impl", parse, nil, nil, parsers = []^Parser{parser, impl})
}

rec :: proc(parser: ^Parser) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (err: ParserError) {
        recursive_rule := self.parsers[0]

        node := new(ExecTree)
        rd := state.rd
        state.rd.exec_trees = map[^Parser]^ExecTree{}
        state.rd.current_node = node

        if err = parser_parse(state, self.parsers[0]); err != nil {
            free(node)
            return err
        }

        if recursive_rule in rd.exec_trees {
            rd.exec_trees[recursive_rule].rhs = state.rd.current_node
            state.rd.exec_trees[recursive_rule] = rd.exec_trees[recursive_rule]
        }

        return nil
    }
    return parser_create("", parse, nil, nil, parsers = []^Parser{parser})
}

// will not parse the inside of the block (used for writing preprocessing tool)
// TODO: block($open: string, $close: string)

// QUESTION: block(open: ^Parser, close: ^Parser) usefull???
