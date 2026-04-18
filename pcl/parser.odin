package pcl

import "core:strings"
import "core:fmt"
import "core:mem"

// parser //////////////////////////////////////////////////////////////////////

Parser :: struct {
    name: string,
    parse: ParseProc,
    skip: SkipCtx, // skip proc
    exec: ExecProc,
    parsers: [dynamic]^Parser,
}

ParseResult :: union {
    ^ExecTreeNode,
    ExecResult,
}

ParseProc :: proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, status: ParserStatus)

ParserAllocator :: mem.Allocator

parser_create_from_dynamic_array_generic :: proc(
    $T: typeid,
    name: string,
    parse: ParseProc,
    skip: SkipCtx,
    exec: ExecProc,
    parsers: [dynamic]^Parser,
) -> ^T {
    parser := new(T)
    parser.name = name
    parser.parse = parse
    parser.skip = skip
    parser.exec = exec
    parser.parsers = parsers
    return parser
}

parser_create_from_slice_generic :: proc(
    $T: typeid,
    name: string,
    parse: ParseProc,
    skip: SkipCtx,
    exec: ExecProc,
    parsers: []^Parser = nil,
) -> ^T {
    parser_array: [dynamic]^Parser
    if parsers != nil && len(parsers) > 0 {
        parser_array = make([dynamic]^Parser, len(parsers))

        for sub_parser, idx in parsers {
            if sub_parser == nil do continue
            parser_array[idx] = sub_parser
        }
    }
    return parser_create_from_dynamic_array_generic(T, name, parse, skip, exec, parser_array)
}

parser_create_from_dynamic_array :: proc(
    name: string,
    parse: ParseProc,
    skip: SkipCtx,
    exec: ExecProc,
    parsers: [dynamic]^Parser,
) -> ^Parser {
    return parser_create_from_dynamic_array_generic(Parser, name, parse, skip, exec, parsers)
}

parser_create_from_slice :: proc(
    name: string,
    parse: ParseProc,
    skip: SkipCtx,
    exec: ExecProc,
    parsers: []^Parser = nil,
) -> ^Parser {
    return parser_create_from_slice_generic(Parser, name, parse, skip, exec, parsers)
}

parser_create :: proc {
    parser_create_from_dynamic_array_generic,
    parser_create_from_slice_generic,
    parser_create_from_dynamic_array,
    parser_create_from_slice,
}

// print grammar ///////////////////////////////////////////////////////////////

parser_print :: proc(parser: ^Parser) {
    // TODO
    // we need a combinator type in the parser
}

// helper functions ////////////////////////////////////////////////////////////

parser_parse :: proc(state: ^ParserState, parser: ^Parser) -> (res: ParseResult, status: ParserStatus) {
    return parser->parse(state)
}

parser_skip :: proc(state: ^ParserState, skip_ctx: SkipCtx) -> (pos: int, loc: Location) {
    if skip_ctx.skip == nil {
        return state.pos, state.loc
    }
    for !state_eof(state) {
        skip_ctx.skip(state, skip_ctx.data) or_break
    }
    state.pos = state.cur
    return state.pos, state.loc
}

// errors //////////////////////////////////////////////////////////////////////

ParserStatus :: enum {
    Success,       // parser success
    ParserFailure, // rule failed (recoverable)
    SyntaxError,   // rule error (non recoverable: expect rule)
    InternalError, // internal error (non recoverable)
}

parser_failure :: proc(state: ^ParserState, parser_name: string) -> ParserStatus {
    state.global_state.error_state.parser_name = parser_name
    state.global_state.error_state.location = state.loc
    return .ParserFailure
}

parser_internal_error :: proc(state: ^ParserState, parser_name: string, message: string) -> ParserStatus {
    state.global_state.error_state.parser_name = parser_name
    state.global_state.error_state.message = message
    return .InternalError
}

parser_can_recover :: proc(status: ParserStatus) -> bool {
    return status == .Success || status == .ParserFailure
}

parser_error_report :: proc(state: ^ParserState, status: ParserStatus) {
    if status == .InternalError {
        fmt.printfln("internal error: {}", state.global_state.error_state.message)
    } else if status == .ParserFailure {
        fmt.printfln("rule `{}' failed.", state.global_state.error_state.parser_name)
        state.loc = state.global_state.error_state.location
        state_print_context(state)
    }
}

// exec tree functions /////////////////////////////////////////////////////////

parser_exec_with_childs :: proc(
    state: ^ParserState,
    exec: ExecProc,
    childs: [dynamic]ParseResult,
    flags: bit_set[ExecFlag] = {},
    loc := #caller_location,
) -> ParseResult {
    if state.global_state.handle.do_not_exec do return nil
    pr: ParseResult
    pr = memory_pool_allocate(&state.global_state.handle.exec_node_pool, loc)
    pr.(^ExecTreeNode).ctx = ExecContext{exec, state^}
    pr.(^ExecTreeNode).flags = flags
    pr.(^ExecTreeNode).childs = childs
    return pr
}

parser_exec_with_child :: proc(
    state: ^ParserState,
    exec: ExecProc,
    result: ParseResult,
    flags: bit_set[ExecFlag] = {},
    loc := #caller_location,
) -> ParseResult {
    if state.global_state.handle.do_not_exec do return nil
    results := make([dynamic]ParseResult, allocator = state.global_state.handle.result_allocator)
    append(&results, result)
    return parser_exec_with_childs(state, exec, results, flags, loc = loc)
}

parser_exec_no_child :: proc(
    state: ^ParserState,
    exec: ExecProc,
    flags: bit_set[ExecFlag] = {},
    loc := #caller_location,
) -> ParseResult {
    if state.global_state.handle.do_not_exec do return nil
    return parser_exec_with_childs(state, exec, [dynamic]ParseResult{}, flags, loc = loc)
}

parser_exec :: proc {
    parser_exec_with_childs,
    parser_exec_with_child,
    parser_exec_no_child,
}
