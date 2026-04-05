package pcl

import "core:fmt"
import "core:log"
import "core:strings"
import "core:slice"
import "core:mem"

// combinator intput type //////////////////////////////////////////////////////

CombinatorInput :: union {
    ^Parser,
    string,
    rune,
}

@(private="package")
create_parser_array :: proc(allocator: mem.Allocator, skip: SkipCtx, inputs: ..CombinatorInput) -> [dynamic]^Parser {
    array := make([dynamic]^Parser, allocator = allocator)

    for input in inputs {
        switch value in input {
        case ^Parser:
            append(&array, value)
        case rune:
            append(&array, lit_c(value, skip = skip))
        case string:
            append(&array, lit_str(value, skip = skip))
        }
    }
    return array
}

release_result :: proc(state: ^ParserState, result: ParseResult) {
    release_exec_tree(&state.pcl_handle.exec_node_pool, result)
}

release_results :: proc(state: ^ParserState, results: []ParseResult) {
    #reverse for result in results {
        release_exec_tree(&state.pcl_handle.exec_node_pool, result)
    }
}

// combinators /////////////////////////////////////////////////////////////////

declare :: proc(name: string = "parser") -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        if len(self.parsers) == 0 || self.parsers[0] == nil {
            return nil, internal_error(state, "unimplemented parser `{}`.", self.name)
        }

        parser_skip(state, self.skip)
        if res, err = parser_parse(state, self.parsers[0]); err != nil {
            return nil, err
        }
        return res, nil
    }
    return parser_create(name, parse, NO_SKIP, nil, []^Parser{nil})
}

define :: proc(
    parser: ^Parser,
    impl: ^Parser,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
) {
    if len(parser.parsers) == 0 {
        fmt.printfln("error: cannot define parser {}.", parser.name)
    }
    if parser.parsers[0] != nil {
        fmt.printfln("error: redifinition of parser {}.", parser.name)
    }
    if impl.exec == nil {
        impl.exec = exec
    }
    impl.name = parser.name
    parser.parsers[0] = impl
    parser.skip = skip
}

parser :: proc(
    rule: ^Parser,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "single",
) -> ^Parser {
    rule.skip = skip
    rule.exec = exec
    rule.name = name
    return rule
}

expect :: proc(parser: CombinatorInput) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        res, err = parser_parse(state, self.parsers[0])
        if err != nil {
            parser_error_report(err)
            err = syntax_error(state, "expected rule failed.")
            parser_fatal_error(&err)
        }
        return res, err
    }
    return parser_create("", parse, NO_SKIP, nil, create_parser_array(context.allocator, NO_SKIP, parser))
}

empty :: proc() -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        return nil, nil
    }
    return parser_create("emtpy", parse, SKIP, nil)
}

single :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "single",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        if res, err = parser_parse(&sub_state, self.parsers[0]); err != nil {
            return nil, err
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, res)
        state_post_exec(state, sub_state.loc)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, input))
}

not :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    name: string = "not",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        sub_state := state^
        parser_skip(&sub_state, self.skip)
        state.pcl_handle.do_not_exec = true
        res, err = parser_parse(&sub_state, self.parsers[0])
        state.pcl_handle.do_not_exec = false
        if err == nil {
            return nil, syntax_error(state, "not parser failed.")
        }
        return nil, nil
    }
    return parser_create(name, parse, skip, nil, create_parser_array(context.allocator, skip, input))
}

opt :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "opt",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        if res, err = parser_parse(&sub_state, self.parsers[0]); err != nil {
            if !parser_can_recover(err) {
                return nil, err
            }
            free_all(state.pcl_handle.error_allocator)
            res = ExecResult{"", state.loc}
            return parser_exec_with_child(state, self.exec, res), nil
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, res)
        state_post_exec(state, sub_state.loc)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, input))
}

/*
 * The or process rules in order, which means that the first rule in the list
 * will be tested before the second. This parser is greedy and will return the
 * first rule that can be applied on the input.
 */
or :: proc(
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "or",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        state_enter_branch(state)
        defer state_leave_branch(state)
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        for parser in self.parsers {
            tmp_sub_state := sub_state
            sub_res: ParseResult
            sub_err: ParserError

            if sub_res, sub_err = parser_parse(&tmp_sub_state, parser); sub_err == nil {
                state_pre_exec(state, pos, tmp_sub_state.cur, loc)
                res = parser_exec(state, self.exec, sub_res)
                state_post_exec(state, tmp_sub_state.loc)
                return res, nil
            }
            if !parser_can_recover(sub_err) {
                return nil, sub_err
            }
            free_all(state.pcl_handle.error_allocator)
        }
        return nil, syntax_error(state, "none of the rules in `{}` could be applied.", self.name)
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

seq :: proc(
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "seq",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult, allocator = state.pcl_handle.tree_allocator)
        sub_state := state^
        sub_res: ParseResult
        pos, loc := parser_skip(&sub_state, self.skip)

        for parser, parser_idx in self.parsers {
            parser_skip(&sub_state, self.skip)
            if sub_res, err = parser_parse(&sub_state, parser); err != nil {
                release_results(state, results[:])
                return nil, err
            }
            append(&results, sub_res)
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, results)
        state_post_exec(state, sub_state.loc)
        return res, nil
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

star :: proc(
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "star",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult, allocator = state.pcl_handle.tree_allocator)
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        for !state_eof(&sub_state) {
            tmp_sub_state := sub_state
            sub_res, sub_err := parser_parse(&tmp_sub_state, self.parsers[0])
            if sub_err != nil {
                if parser_can_recover(sub_err) {
                    break
                } else {
                    release_results(state, results[:])
                    return nil, sub_err
                }
            }
            append(&results, sub_res)
            sub_state = tmp_sub_state
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, results, flags = {.ListResult})
        state_post_exec(state, sub_state.loc)
        return res, nil
    }
    if len(inputs) > 1 {
        return parser_create(name, parse, skip, exec, []^Parser{seq(..inputs, skip = skip)})
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

plus :: proc(
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "plus",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult, allocator = state.pcl_handle.tree_allocator)
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        for !state_eof(&sub_state) {
            tmp_sub_state := sub_state
            sub_res, sub_err := parser_parse(&tmp_sub_state, self.parsers[0])
            if sub_err != nil {
                if parser_can_recover(sub_err) {
                    break
                } else {
                    release_results(state, results[:])
                    return nil, sub_err
                }
            }
            append(&results, sub_res)
            sub_state = tmp_sub_state
        }
        if sub_state.cur > pos {
            state_pre_exec(state, pos, sub_state.cur, loc)
            res = parser_exec(state, self.exec, results, flags = {.ListResult})
            state_post_exec(state, sub_state.loc)
            return res, nil
        }
        return nil, syntax_error(state, "rule {%s}+ failed.", self.parsers[0].name)
    }
    if len(inputs) > 1 {
        return parser_create(name, parse, skip, exec, []^Parser{seq(..inputs, skip = skip)})
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

times :: proc(
    $nb_times: int,
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "times",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        results := make([dynamic]ParseResult, allocator = state.pcl_handle.tree_allocator)
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)
        count := 0

        for !state_eof(&sub_state) && count < nb_times {
            sub_res := parser_parse(&sub_state, self.parsers[0]) or_break
            append(&results, sub_res)
            count += 1
        }
        if count == nb_times {
            state_pre_exec(state, pos, sub_state.cur, loc)
            res = parser_exec(state, self.exec, results, flags = {.ListResult})
            state_post_exec(state, sub_state.loc)
            return res, nil
        }
        release_results(state, results[:])
        return nil, syntax_error(state, "rule {%s}{%d} failed (%d found)",
                                 self.parsers[0].name, nb_times, count)
    }
    if len(inputs) > 1 {
        return parser_create(name, parse, skip, exec, []^Parser{seq(..inputs, skip = skip)})
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
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
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "single",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        state.pcl_handle.do_not_exec = true
        res, err = parser_parse(&sub_state, self.parsers[0])
        state.pcl_handle.do_not_exec = false
        if err != nil {
            return nil, err
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec)
        state_post_exec(state, sub_state.loc)
        return res, nil
    }
    if len(inputs) > 1 {
        return parser_create(name, parse, skip, exec, []^Parser{seq(..inputs, skip = skip)})
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

// reset the top nodes for left recursive grammars
rec :: proc(parser: ^Parser) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        recursive_rule := self.parsers[0]

        old_top_nodes := state.pcl_handle.rd.top_nodes
        state.pcl_handle.rd.top_nodes = make(map[^Parser]ParseResult)
        defer {
            delete(state.pcl_handle.rd.top_nodes)
            state.pcl_handle.rd.top_nodes = old_top_nodes
        }

        if res, err = parser_parse(state, self.parsers[0]); err != nil {
            return nil, err
        }
        return res, nil
    }
    return parser_create("", parse, NO_SKIP, nil, []^Parser{parser})
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
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "lrec",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError) {
        state_enter_lrec(state)
        defer state_leave_lrec(state)

        recursive_rule := self.parsers[0]
        terminal_rule := self.parsers[len(self.parsers) - 1]
        middle_rules := self.parsers[1:len(self.parsers) - 1]
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        if res, err = parser_parse(&sub_state, terminal_rule); err != nil {
            return nil, err
        }

        if recursive_rule in state.pcl_handle.rd.top_nodes {
            state.pcl_handle.rd.top_nodes[recursive_rule].(^ExecTreeNode).childs[len(self.parsers) - 1] = res
            state.pcl_handle.rd.top_nodes[recursive_rule].(^ExecTreeNode).ctx.state.cur = state.pos
            res = state.pcl_handle.rd.top_nodes[recursive_rule]
        }

        // success if eof and no operator
        parser_skip(&sub_state, self.skip)
        if state_eof(&sub_state) || len(middle_rules) == 0 {
            delete_key(&state.pcl_handle.rd.top_nodes, recursive_rule)
            log.info("res(eof):", self.name, state.content[sub_state.pos:])
            // if we return we have to update the state; we do not execute here
            // (no need to: string empty, or no middel rules)
            state_pre_exec(state, pos, sub_state.cur, loc)
            state_post_exec(state, sub_state.loc)
            return res, nil
        }


        childs := make([dynamic]ParseResult, len(self.parsers), allocator = state.pcl_handle.tree_allocator)
        childs[0] = res

        // apply middle rules
        for parser, idx in middle_rules {
            parser_skip(&sub_state, self.skip)
            if res, err = parser_parse(&sub_state, parser); err != nil {
                release_results(state, childs[:idx])
                delete(childs)
                return nil, err
            }
            childs[1 + idx] = res
        }

        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, childs)
        state_post_exec(state, sub_state.loc)
        res.(^ExecTreeNode).ctx.state.pos = childs[0].(^ExecTreeNode).ctx.state.pos
        state.pcl_handle.rd.top_nodes[recursive_rule] = res

        // apply recursive rule
        if res, err = parser_parse(state, recursive_rule); err != nil {
            release_result(state, res)
            return nil, err
        }

        if recursive_rule in state.pcl_handle.rd.top_nodes {
            res = state.pcl_handle.rd.top_nodes[recursive_rule]
            delete_key(&state.pcl_handle.rd.top_nodes, recursive_rule)
        }
        return res, nil
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}
