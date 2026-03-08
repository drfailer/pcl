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

ParseProc :: proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError)

ParserAllocator :: mem.Allocator

parser_allocator_create :: proc() -> ParserAllocator {
    arena := new(mem.Dynamic_Arena)
    mem.dynamic_arena_init(arena)
    return mem.dynamic_arena_allocator(arena)
}

parser_allocator_destroy :: proc(allocator: ParserAllocator) {
    arena := cast(^mem.Dynamic_Arena)allocator.data
    mem.dynamic_arena_destroy(arena)
    free(arena)
}

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

parser_parse :: proc(state: ^ParserState, parser: ^Parser) -> (res: ParseResult, err: ParserError) {
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

SyntaxError :: struct {
    state: ParserState,
    message: string,
    fatal: bool,
}

InternalError :: struct {
    message: string,
}

ParserError :: union {
    SyntaxError,
    InternalError,
}

internal_error :: proc(state: ^ParserState, str: string, args: ..any) -> ParserError {
    return InternalError{
        fmt.aprintf(str, ..args, allocator = state.pcl_handle.error_allocator)
    }
}

syntax_error :: proc(state: ^ParserState, str: string, args: ..any, fatal := false) -> ParserError {
    return SyntaxError{
        state^,
        fmt.aprintf(str, ..args, allocator = state.pcl_handle.error_allocator),
        fatal,
    }
}

parser_fatal_error :: proc(error: ^ParserError) {
    #partial switch &e in error {
    case (SyntaxError): e.fatal = true
    }
}

parser_can_recover :: proc(error: ParserError) -> bool {
    switch e in error {
    case InternalError: return false
    case SyntaxError: return e.fatal == false
    }
    return true
}

parser_error_report :: proc(error: ParserError) {
    switch e in error {
    case SyntaxError:
        fmt.printfln("syntax error: {}", e.message)
        state := e.state
        state_print_context(&state)
    case InternalError:
        fmt.printfln("internal error: {}", e.message)
    }
}

// exec tree functions /////////////////////////////////////////////////////////

parser_exec_with_childs :: proc(
    state: ^ParserState,
    exec: ExecProc,
    childs: [dynamic]ParseResult,
    flags: bit_set[ExecFlag] = {},
) -> ParseResult {
    if state.pcl_handle.do_not_exec do return nil
    loc := state.loc
    pr: ParseResult
    pr = memory_pool_allocate(&state.pcl_handle.exec_node_pool)
    pr.(^ExecTreeNode).ctx = ExecContext{exec, state^}
    pr.(^ExecTreeNode).flags = flags
    pr.(^ExecTreeNode).childs = childs
    return pr
}

parser_exec_with_child :: proc(state: ^ParserState, exec: ExecProc, result: ParseResult, flags: bit_set[ExecFlag] = {}) -> ParseResult {
    if state.pcl_handle.do_not_exec do return nil
    results := make([dynamic]ParseResult, allocator = state.pcl_handle.tree_allocator)
    append(&results, result)
    return parser_exec_with_childs(state, exec, results, flags)
}

parser_exec_no_child :: proc(state: ^ParserState, exec: ExecProc, flags: bit_set[ExecFlag] = {}) -> ParseResult {
    if state.pcl_handle.do_not_exec do return nil
    return parser_exec_with_childs(state, exec, [dynamic]ParseResult{}, flags)
}

parser_exec :: proc {
    parser_exec_with_childs,
    parser_exec_with_child,
    parser_exec_no_child,
}
