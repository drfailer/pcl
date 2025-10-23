package pcl

import "core:fmt"
import "core:strings"
import "core:slice"
import "core:mem"

// combinator intput type //////////////////////////////////////////////////////

CombinatorInput :: union {
    ^Parser,
    string,
    rune,
}

@(private="file")
create_parser_array :: proc(allocator: mem.Allocator, inputs: ..CombinatorInput) -> [dynamic]^Parser {
    array := make([dynamic]^Parser, allocator = allocator)

    for input in inputs {
        switch value in input {
        case ^Parser:
            append(&array, value)
        case rune:
            // TODO
        case string:
            // TODO
        }
    }
    return array
}

// configuration varibles //////////////////////////////////////////////////////

SKIP: PredProc = nil

// combinators /////////////////////////////////////////////////////////////////

declare :: proc(
    name: string = "parser",
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        if len(self.parsers) == 0 || self.parsers[0] == nil {
            return nil, parser_error(InternalError, state, "unimplemented parser `{}`.", self.name)
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
    impl.name = parser.name
    parser.parsers[0] = impl
}

empty :: proc() -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        return nil, nil
    }
    return parser_create("emtpy", parse, SKIP, nil)
}

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
            state_set(state, &sub_state)
            return nil, err
        }
        state_set(state, &sub_state)
        if self.exec != nil {
            res = parser_exec(state, self.exec, res)
        }
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
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
            // ISSUE: this allow to transmit error message when the optional
            //        parser failed but did consume a part of the string (in
            //        this case, the content was there, but contained an error).
            //        However, this will not work if the `skip` of the sub-rule
            //        is different than the skip of this rule.
            if (self.parsers[0].skip == nil || self.parsers[0].skip == self.skip) && sub_state.cur > state.cur {
                state_set(state, &sub_state)
                return nil, err
            }
            return nil, nil
        }
        free_all(state.global_state.error_allocator)
        state_set(state, &sub_state)
        if self.exec != nil {
            res = parser_exec(state, self.exec, res)
        }
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
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
            sub_res: ParseResult
            sub_err: ParserError

            if sub_res, sub_err = parser_parse(&sub_state, parser); sub_err == nil {
                state_set(state, &sub_state)
                res = parser_exec(state, self.exec, sub_res)
                state_save_pos(state)
                return res, nil
            }
            free_all(state.global_state.error_allocator)
        }
        return nil, parser_error(SyntaxError, state, "none of the rules in `{}` could be applied.", self.name)
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

seq :: proc(
    parsers: ..^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "seq",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult, allocator = state.global_state.tree_allocator)
        sub_state := state^
        sub_res: ParseResult

        for parser, parser_idx in self.parsers {
            parser_skip(&sub_state, self.skip)
            if sub_res, err = parser_parse(&sub_state, parser); err != nil {
                state_set(state, &sub_state)
                switch e in err {
                case InternalError:
                    return nil, err
                case SyntaxError:
                    return nil, parser_error(SyntaxError, state, "{}[{}]: {}",
                                             self.name, parser_idx, e.message)
                }
            }
            append(&results, sub_res)
            state_set(state, &sub_state)
        }
        res = parser_exec(state, self.exec, results)
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}

star :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "star",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult, allocator = state.global_state.tree_allocator)

        parser_skip(state, self.skip)
        sub_state := state^
        for !state_eof(state) {
            sub_res := parser_parse(&sub_state, self.parsers[0]) or_break
            append(&results, sub_res)
            state_set(state, &sub_state)
        }
        if state.cur > state.pos {
            res = parser_exec(state, self.exec, results)
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
        results := make([dynamic]ParseResult, allocator = state.global_state.tree_allocator)

        parser_skip(state, self.skip)
        sub_state := state^
        for !state_eof(state) {
            sub_res := parser_parse(&sub_state, self.parsers[0]) or_break
            append(&results, sub_res)
            state_set(state, &sub_state)
        }
        if state.cur > state.pos {
            res = parser_exec(state, self.exec, results)
            state_save_pos(state)
            return res, nil
        }
        return nil, parser_error(SyntaxError, state, "rule {%s}+ failed.", self.parsers[0].name)
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
        results := make([dynamic]ParseResult, allocator = state.global_state.tree_allocator)
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
            res = parser_exec(state, self.exec, results)
            state_save_pos(state)
            return res, nil
        }
        return nil, parser_error(SyntaxError, state, "rule {%s}{%d} failed (%d found)",
                                 self.parsers[0].name, nb_times, count)
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

/*
 * This parser is used when we need to combine parsers but run the execution
 * function on the whole parsed string.
 *
 * Example:
 *
 * normal_rule := seq(rang('0', '9'), exec = foo)
 * parse("12345") => foo(["1", "2", "3", "4", "5"])
 *
 * combined_rule := combine(seq(rang('0', '9')), exec = foo)
 * parse("12345") => foo(["12345"])
 */
combine :: proc(
    parser: ^Parser,
    skip: PredProc = SKIP,
    exec: ExecProc = nil,
    name: string = "single",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        parser_skip(state, self.skip)
        pos := state.pos
        if res, err = parser_parse(state, self.parsers[0]); err != nil {
            return nil, err
        }
        state.pos = pos
        res = parser_exec(state, self.exec)
        state_save_pos(state)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = []^Parser{parser})
}

rec :: proc(parser: ^Parser) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        recursive_rule := self.parsers[0]

        old_top_nodes := state.global_state.rd.top_nodes
        state.global_state.rd.top_nodes = make(map[^Parser]^ExecTreeNode)
        defer {
            delete(state.global_state.rd.top_nodes)
            state.global_state.rd.top_nodes = old_top_nodes
        }

        if res, err = parser_parse(state, self.parsers[0]); err != nil {
            return nil, err
        }
        return res, nil
    }
    return parser_create("", parse, nil, nil, parsers = []^Parser{parser})
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

        state.global_state.rd.depth += 1

        // apply terminal rule
        parser_skip(state, self.skip)
        if res, err = parser_parse(state, terminal_rule); err != nil {
            return nil, err
        }

        if recursive_rule in state.global_state.rd.top_nodes {
            state.global_state.rd.top_nodes[recursive_rule].childs[len(self.parsers) - 1] = res
            state.global_state.rd.top_nodes[recursive_rule].ctx.state.cur = state.pos
            res = state.global_state.rd.top_nodes[recursive_rule]
        }

        // success if eof and no operator
        parser_skip(state, self.skip)
        if state_eof(state) && len(middle_rules) == 0 {
            delete_key(&state.global_state.rd.top_nodes, recursive_rule)
            return res, nil
        }


        childs := make([dynamic]^ExecTreeNode, len(self.parsers), allocator = state.global_state.tree_allocator)
        childs[0] = res

        // apply middle rules
        for parser, idx in middle_rules {
            parser_skip(state, self.skip)
            if res, err = parser_parse(state, parser); err != nil {
                return nil, err
            }
            childs[1 + idx] = res
        }

        parser_skip(state, self.skip)
        res = parser_exec(state, self.exec, childs)
        res.ctx.state.pos = childs[0].ctx.state.pos
        state.global_state.rd.top_nodes[recursive_rule] = res

        // apply recursive rule
        if res, err = parser_parse(state, recursive_rule); err != nil {
            return nil, err
        }

        state.global_state.rd.depth -= 1
        if recursive_rule in state.global_state.rd.top_nodes {
            res = state.global_state.rd.top_nodes[recursive_rule]
            delete_key(&state.global_state.rd.top_nodes, recursive_rule)
        }

        if state.global_state.rd.depth == 0 {
            clear(&state.global_state.rd.top_nodes)
        }
        return res, nil
    }
    return parser_create(name, parse, skip, exec, parsers = parsers)
}
