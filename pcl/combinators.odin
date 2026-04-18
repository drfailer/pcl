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
    release_exec_tree(&state.global_state.handle.exec_node_pool, result)
}

release_results :: proc(state: ^ParserState, results: []ParseResult) {
    #reverse for result in results {
        release_exec_tree(&state.global_state.handle.exec_node_pool, result)
    }
}

// combinators /////////////////////////////////////////////////////////////////

declare :: proc(name: string = "parser") -> ^Parser {
    // we need to have this intermediate parse function in case the definition
    // of the parser is a special type (we can't just swap a normal parser with
    // a specialized one, otherwise it would result in a bad cast in the
    // underlying parse proc).
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        assert(len(self.parsers) > 0 && self.parsers[0] != nil, "declared parsers must be defined.")
        return parser_parse(state, self.parsers[0])
    }
    return parser_create(name, parse, NO_SKIP, nil, []^Parser{nil})
}

declare_lrec :: proc(name: string = "lrec_parser") -> ^Parser {
    parse := proc(parser: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        self := cast(^LRecParser)parser
        assert(len(self.parsers) > 0 && self.parsers[0] != nil, "declared parsers must be defined.")
        // depth
        depth_save := self.depth
        defer self.depth = depth_save
        // rhs
        rhs_save := self.rhs
        self.rhs = nil
        defer if rhs_save != nil do self.rhs = rhs_save
        // run the parser
        res, status = parser_parse(state, self.parsers[0])
        return res, status
    }
    return parser_create(LRecParser, name, parse, NO_SKIP, nil, []^Parser{nil})
}

define :: proc(
    parser: ^Parser,
    impl: ^Parser,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
) {
    if len(parser.parsers) == 0 do fmt.printfln("error: cannot define parser {}.", parser.name)
    if parser.parsers[0] != nil do fmt.printfln("error: redifinition of parser {}.", parser.name)
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

ExpectParser :: struct {
    using parser: Parser,
    message: string,
}

expect :: proc(parser: CombinatorInput, message :=  "") -> ^Parser {
    parse := proc(parser: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        self := cast(^ExpectParser)parser
        res, status = parser_parse(state, self.parsers[0])
        if status == .ParserFailure {
            if len(self.message) > 0 {
                fmt.printfln("syntax error: {}", self.message)
                state_print_context(state)
            } else {
                fmt.printf("syntax error: ")
                parser_error_report(state, status)
            }
            return nil, .SyntaxError
        }
        return res, status
    }
    result := parser_create(ExpectParser, "", parse, NO_SKIP, nil,
                            create_parser_array(context.allocator, NO_SKIP, parser))
    result.message = message
    return result
}

empty :: proc() -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        return nil, .Success
    }
    return parser_create("emtpy", parse, SKIP, nil)
}

single :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "single",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        if res, status = parser_parse(&sub_state, self.parsers[0]); status != .Success {
            return nil, status
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, res)
        state_post_exec(state, sub_state.loc)
        return res, .Success
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, input))
}

not :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    name: string = "not",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        sub_state := state^
        parser_skip(&sub_state, self.skip)
        state.global_state.handle.do_not_exec = true
        res, status = parser_parse(&sub_state, self.parsers[0])
        state.global_state.handle.do_not_exec = false
        if status == .Success {
            return nil, .ParserFailure // we don't register the location here
        }
        return nil, .Success
    }
    return parser_create(name, parse, skip, nil, create_parser_array(context.allocator, skip, input))
}

opt :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "opt",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        if res, status = parser_parse(&sub_state, self.parsers[0]); status != nil {
            if !parser_can_recover(status) {
                return nil, status
            }
            res = ExecResult{"", state.loc}
            return parser_exec_with_child(state, self.exec, res), .Success
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, res)
        state_post_exec(state, sub_state.loc)
        return res, .Success
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        state_enter_branch(state)
        defer state_leave_branch(state)
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        for parser in self.parsers {
            tmp_sub_state := sub_state
            sub_res: ParseResult
            sub_status: ParserStatus

            if sub_res, sub_status = parser_parse(&tmp_sub_state, parser); sub_status == .Success {
                state_pre_exec(state, pos, tmp_sub_state.cur, loc)
                res = parser_exec(state, self.exec, sub_res)
                state_post_exec(state, tmp_sub_state.loc)
                return res, .Success
            }
            if !parser_can_recover(sub_status) {
                return nil, sub_status
            }
        }
        return nil, parser_failure(state, self.name)
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

seq :: proc(
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "seq",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        results := make([dynamic]ParseResult, allocator = state.global_state.handle.result_allocator)
        sub_state := state^
        sub_res: ParseResult
        pos, loc := parser_skip(&sub_state, self.skip)

        for parser, parser_idx in self.parsers {
            parser_skip(&sub_state, self.skip)
            if sub_res, status = parser_parse(&sub_state, parser); status != .Success {
                release_results(state, results[:])
                return nil, status
            }
            append(&results, sub_res)
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, results)
        state_post_exec(state, sub_state.loc)
        return res, .Success
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

star :: proc(
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "star",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        results := make([dynamic]ParseResult, allocator = state.global_state.handle.result_allocator)
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        for !state_eof(&sub_state) {
            tmp_sub_state := sub_state
            sub_res, sub_status := parser_parse(&tmp_sub_state, self.parsers[0])
            if sub_status != .Success {
                if parser_can_recover(sub_status) {
                    break
                } else {
                    release_results(state, results[:])
                    return nil, sub_status
                }
            }
            append(&results, sub_res)
            sub_state = tmp_sub_state
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, results, flags = bit_set[ExecFlag]{.ListResult})
        state_post_exec(state, sub_state.loc)
        return res, .Success
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        results := make([dynamic]ParseResult, allocator = state.global_state.handle.result_allocator)
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        for !state_eof(&sub_state) {
            tmp_sub_state := sub_state
            sub_res, sub_status := parser_parse(&tmp_sub_state, self.parsers[0])
            if sub_status != .Success {
                if parser_can_recover(sub_status) {
                    break
                } else {
                    release_results(state, results[:])
                    return nil, sub_status
                }
            }
            append(&results, sub_res)
            sub_state = tmp_sub_state
        }
        if sub_state.cur > pos {
            state_pre_exec(state, pos, sub_state.cur, loc)
            res = parser_exec(state, self.exec, results, flags = bit_set[ExecFlag]{.ListResult})
            state_post_exec(state, sub_state.loc)
            return res, .Success
        }
        return nil, parser_failure(state, self.name)
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        results := make([dynamic]ParseResult, allocator = state.global_state.handle.result_allocator)
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
            res = parser_exec(state, self.exec, results, flags = bit_set[ExecFlag]{.ListResult})
            state_post_exec(state, sub_state.loc)
            return res, .Success
        }
        release_results(state, results[:])
        return nil, parser_failure(state, self.name)
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        state.global_state.handle.do_not_exec = true
        res, status = parser_parse(&sub_state, self.parsers[0])
        state.global_state.handle.do_not_exec = false
        if status != .Success {
            return nil, status
        }
        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec)
        state_post_exec(state, sub_state.loc)
        return res, .Success
    }
    if len(inputs) > 1 {
        return parser_create(name, parse, skip, exec, []^Parser{seq(..inputs, skip = skip)})
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

// left recursive parser ///////////////////////////////////////////////////////

LRecParser :: struct {
    using parser: Parser,
    depth: u64,
    rhs: ParseResult,
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
    inputs: ..CombinatorInput, // TODO: force lrec parser as input
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "lrec",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus) {
        terminal_rule := self.parsers[len(self.parsers) - 1]
        recursive_rule := cast(^LRecParser)self.parsers[0]
        middle_rules := self.parsers[1:len(self.parsers) - 1]
        sub_state := state^
        pos, loc := parser_skip(&sub_state, self.skip)

        state_enter_lrec(state, recursive_rule)
        defer state_leave_lrec(state, recursive_rule)

        if res, status = parser_parse(&sub_state, terminal_rule); status != .Success {
            return nil, status
        }
        term_res := res // we save the term rule for free
        res = lrec_update_rhs(self, state, res, sub_state.cur)

        // success if eof and no operator
        parser_skip(&sub_state, self.skip)
        if state_eof(&sub_state) && len(middle_rules) == 0 {
            // if we return we have to update the state; we do not execute here
            // (no need to: string empty, or no middel rules)
            state_pre_exec(state, pos, sub_state.cur, loc)
            state_post_exec(state, sub_state.loc)
            return res, nil
        }

        childs: [dynamic]ParseResult
        if childs, status = lrec_apply_middle_rules(self, &sub_state); status != .Success {
            if recursive_rule.rhs == nil {
                release_result(state, term_res)
            }
            return nil, status
        }
        childs[0] = res

        state_pre_exec(state, pos, sub_state.cur, loc)
        res = parser_exec(state, self.exec, childs)
        state_post_exec(state, sub_state.loc)
        res.(^ExecTreeNode).ctx.state.pos = childs[0].(^ExecTreeNode).ctx.state.pos
        recursive_rule.rhs = res

        // apply recursive rule
        if res, status = parser_parse(state, recursive_rule.parsers[0]); status != .Success {
            // apparently, we never end up here
            return nil, status
        }
        // TODO: why?
        if recursive_rule.rhs != nil && recursive_rule.rhs.(^ExecTreeNode) != res.(^ExecTreeNode) {
            release_result(state, res)
            res = recursive_rule.rhs
            recursive_rule.rhs = nil
        }
        return res, .Success
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

@(private="file")
lrec_update_rhs :: proc(self: ^Parser, state: ^ParserState, rhs: ParseResult, cur: int) -> (lhs: ParseResult) {
    recursive_rule := cast(^LRecParser)self.parsers[0]
    if recursive_rule.rhs != nil {
        rhs_idx := len(self.parsers) - 1
        release_result(state, recursive_rule.rhs.(^ExecTreeNode).childs[rhs_idx])
        recursive_rule.rhs.(^ExecTreeNode).childs[rhs_idx] = rhs
        recursive_rule.rhs.(^ExecTreeNode).ctx.state.cur = cur
        return recursive_rule.rhs
    }
    return rhs
}

@(private="file")
lrec_apply_middle_rules :: proc(self: ^Parser, state: ^ParserState) -> (results: [dynamic]ParseResult, status: ParserStatus) {
    middle_rules := self.parsers[1:len(self.parsers) - 1]
    res: ParseResult

    results = make([dynamic]ParseResult, len(self.parsers), allocator = state.global_state.handle.result_allocator)
    for parser, idx in middle_rules {
        parser_skip(state, self.skip)
        if res, status = parser_parse(state, parser); status != .Success {
            release_results(state, results[:])
            delete(results)
            return nil, status
        }
        results[idx + 1] = res
    }
    return results, .Success
}
