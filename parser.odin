package pcl

import "core:strings"
import "core:fmt"
import "core:log"
import "core:mem"

// parser //////////////////////////////////////////////////////////////////////

Parser :: struct {
    name: string,
    parse: ParseProc,
    skip: SkipCtx, // skip proc
    exec: ExecProc,
    parsers: [dynamic]^Parser,
}

ParseProc :: proc(self: ^Parser, state: ^ParserState) -> (status: ParserStatus)

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

parser_parse :: proc(state: ^ParserState, parser: ^Parser) -> (status: ParserStatus) {
    return parser->parse(state)
}

parser_skip :: proc(state: ^ParserState, skip_ctx: SkipCtx) -> ParserStateCursors {
    if skip_ctx.skip == nil {
        return state.cursors
    }
    for !state_eof(state) {
        skip_ctx.skip(state, skip_ctx.data) or_break
    }
    state.cursors.pos = state.cursors.cur
    return state.cursors
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
    state.global_state.error_state.location = state.cursors.loc
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
        state.cursors.loc = state.global_state.error_state.location
        state_print_context(state)
    }
}

// exec tree functions /////////////////////////////////////////////////////////

// FIXME: the sequence parser processes the rules in order which means that we
//        should execute the current rule after the sub rules and process the
//        exec list in order. This means that the lrec parser will need to
//        patch the exec list.

parser_exec_list_len :: proc(state: ^ParserState) -> int {
    if state.global_state.handle.do_not_exec do return -1
    return len(state.global_state.exec_list)
}

parser_exec :: proc(state: ^ParserState, exec: ExecProc, cursors: ParserStateCursors, loc := #caller_location) {
    if state.global_state.handle.do_not_exec || exec == nil do return
    cursors := cursors
    cursors.cur = state.cursors.cur
    append(&state.global_state.exec_list, ExecContext{
        exec = exec,
        cursors = cursors,
    })
}

parser_revert_exec :: proc(state: ^ParserState, index: int, loc := #caller_location) {
    if state.global_state.handle.do_not_exec || index < 0 do return
    resize(&state.global_state.exec_list, index)
}

parser_parse_fail :: proc(
    state: ^ParserState,
    cursors: ParserStateCursors,
    exec_len: int,
    status: ParserStatus,
    loc := #caller_location,
) -> ParserStatus {
    state.cursors = cursors
    parser_revert_exec(state, exec_len, loc)
    return status
}

parser_parse_success :: proc(
    state: ^ParserState,
    exec: ExecProc,
    cursors: ParserStateCursors,
    loc := #caller_location,
) -> ParserStatus {
    parser_exec(state, exec, cursors)
    return .Success
}
