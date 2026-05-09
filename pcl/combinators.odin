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

// combinators /////////////////////////////////////////////////////////////////

declare :: proc(name: string = "parser") -> ^Parser {
    // we need to have this intermediate parse function in case the definition
    // of the parser is a special type (we can't just swap a normal parser with
    // a specialized one, otherwise it would result in a bad cast in the
    // underlying parse proc).
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        assert(len(self.parsers) > 0 && self.parsers[0] != nil, "declared parsers must be defined.")
        return parser_parse(state, self.parsers[0])
    }
    return parser_create(name, parse, NO_SKIP, nil, []^Parser{nil})
}

declare_lrec :: proc(name: string = "lrec_parser") -> ^Parser {
    parse := proc(parser: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        self := cast(^LRecParser)parser
        assert(len(self.parsers) > 0 && self.parsers[0] != nil, "declared parsers must be defined.")
        // depth
        depth_save := self.depth
        defer self.depth = depth_save
        // rhs
        rhs_save := self.rhs
        self.rhs = -1
        defer if rhs_save != -1 do self.rhs = rhs_save
        // run the parser
        return parser_parse(state, self.parsers[0])
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
    parse := proc(parser: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        self := cast(^ExpectParser)parser
        status = parser_parse(state, self.parsers[0])
        if status == .ParserFailure {
            if len(self.message) > 0 {
                fmt.printfln("syntax error: {}", self.message)
                state_print_context(state)
            } else {
                fmt.printf("syntax error: ")
                parser_error_report(state, status)
            }
            return .SyntaxError
        }
        return status
    }
    result := parser_create(ExpectParser, "", parse, NO_SKIP, nil,
                            create_parser_array(context.allocator, NO_SKIP, parser))
    result.message = message
    return result
}

empty :: proc() -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        return .Success
    }
    return parser_create("emtpy", parse, SKIP, nil)
}

single :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "single",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        if status = parser_parse(state, self.parsers[0]); status != .Success {
            return parser_parse_fail(state, cursors, exec_len, status)
        }
        return parser_parse_success(state, self.exec, cursors)
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, input))
}

not :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    name: string = "not",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        state.global_state.handle.do_not_exec = true
        status = parser_parse(state, self.parsers[0])
        state.global_state.handle.do_not_exec = false
        if status == .Success {
            return parser_failure(state, self.name)
        }
        return .Success
    }
    return parser_create(name, parse, skip, nil, create_parser_array(context.allocator, skip, input))
}

opt :: proc(
    input: CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "opt",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        if status = parser_parse(state, self.parsers[0]); status != .Success {
            if status != .ParserFailure {
                return parser_parse_fail(state, cursors, exec_len, status)
            }
        }
        return parser_parse_success(state, self.exec, cursors)
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        state_enter_branch(state)
        defer state_leave_branch(state)
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        for parser in self.parsers {
            if status = parser_parse(state, parser); status == .Success {
                return parser_parse_success(state, self.exec, cursors)
            }
            if status != .ParserFailure {
                return parser_parse_fail(state, cursors, exec_len, status)
            }
        }
        return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

seq :: proc(
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "seq",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        for parser, parser_idx in self.parsers {
            parser_skip(state, self.skip)
            if status = parser_parse(state, parser); status != .Success {
                return parser_parse_fail(state, cursors, exec_len, status)
            }
        }
        return parser_parse_success(state, self.exec, cursors)
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

star :: proc(
    inputs: ..CombinatorInput,
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "star",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        for !state_eof(state) {
            status = parser_parse(state, self.parsers[0])
            if status != .Success {
                if status == .ParserFailure {
                    break
                } else {
                    return parser_parse_fail(state, cursors, exec_len, status)
                }
            }
        }
        return parser_parse_success(state, self.exec, cursors)
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        for !state_eof(state) {
            status := parser_parse(state, self.parsers[0])
            if status != .Success {
                if status == .ParserFailure {
                    break
                } else {
                    return parser_parse_fail(state, cursors, exec_len, status)
                }
            }
        }
        if state.cursors.cur > cursors.pos {
            return parser_parse_success(state, self.exec, cursors)
        }
        return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)
        count := 0

        for !state_eof(state) && count < nb_times {
            parser_parse(state, self.parsers[0]) or_break
            count += 1
        }
        if count == nb_times {
            return parser_parse_success(state, self.exec, cursors)
        }
        return parser_parse_fail(state, cursors, exec_len, parser_failure(state, self.name))
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
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        state.global_state.handle.do_not_exec = true
        status = parser_parse(state, self.parsers[0])
        state.global_state.handle.do_not_exec = false
        if status != .Success {
            return parser_parse_fail(state, cursors, exec_len, status)
        }
        return parser_parse_success(state, self.exec, cursors)
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
    rhs: int,
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
// FIXME: the exec list should be reordered!
lrec :: proc(
    inputs: ..CombinatorInput, // TODO: force lrec parser as input
    skip: SkipCtx = SKIP,
    exec: ExecProc = nil,
    name: string = "lrec",
) -> ^Parser {
    parse := proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
        terminal_rule := self.parsers[len(self.parsers) - 1]
        recursive_rule := cast(^LRecParser)self.parsers[0]
        middle_rules := self.parsers[1:len(self.parsers) - 1]
        cursors := parser_skip(state, self.skip)
        exec_len := parser_exec_list_len(state)

        state_enter_lrec(state, recursive_rule)
        defer state_leave_lrec(state, recursive_rule)

        if status = parser_parse(state, terminal_rule); status != .Success {
            // FIXME: the cursors might be wrong here
            return parser_parse_success(state, self.exec, cursors)
        }

        // success if eof and no operator
        parser_skip(state, self.skip)
        if state_eof(state) && len(middle_rules) == 0 {
            return parser_parse_success(state, self.exec, cursors)
        }

        if status = lrec_apply_middle_rules(self, state); status != .Success {
            return parser_parse_fail(state, cursors, exec_len, status)
        }

        // FIXME: before we needed to udpate the rhs here, but now the order should be maintained naturaly

        // Since the left recursion grammar is supposed to match empty (cf
        // upper comment), the recursive rule is expected to succeed.
        status = parser_parse(state, recursive_rule.parsers[0])
        assert(status == .Success)
        return parser_parse_success(state, self.exec, cursors)
    }
    return parser_create(name, parse, skip, exec, create_parser_array(context.allocator, skip, ..inputs))
}

@(private="file")
lrec_apply_middle_rules :: proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus) {
    middle_rules := self.parsers[1:len(self.parsers) - 1]
    for parser, idx in middle_rules {
        parser_skip(state, self.skip)
        if status = parser_parse(state, parser); status != .Success {
            return status
        }
    }
    return .Success
}
