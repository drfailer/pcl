package pcl

import "core:strings"
import "core:fmt"
import "core:mem"

// parser //////////////////////////////////////////////////////////////////////

Parser :: struct {
    name: string,
    parse: ParseProc,
    skip: SkipProc, // skip proc
    exec: ExecProc,
    parsers: [dynamic]^Parser,
}

ParseResult :: union {
    ^ExecTreeNode,
    ExecResult,
}


SkipProc :: proc(c: rune) -> bool // TODO: should it take the state?

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
    skip: SkipProc,
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
    skip: SkipProc,
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
    skip: SkipProc,
    exec: ExecProc,
    parsers: [dynamic]^Parser,
) -> ^Parser {
    return parser_create_from_dynamic_array_generic(Parser, name, parse, skip, exec, parsers)
}

parser_create_from_slice :: proc(
    name: string,
    parse: ParseProc,
    skip: SkipProc,
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

parser_skip :: proc(state: ^ParserState, parser_skip: SkipProc) {
    if parser_skip == nil {
        return
    }
    state := state
    for !state_eof(state) && parser_skip(state_char(state)) {
        state_eat_one(state) or_break
    }
    state_save_pos(state)
}

// errors //////////////////////////////////////////////////////////////////////

SyntaxError :: struct {
    message: string,
}

InternalError :: struct {
    message: string,
}

ParserError :: union {
    SyntaxError,
    InternalError,
}

parser_error :: proc($error_type: typeid, state: ^ParserState, str: string, args: ..any) -> ParserError {
    return error_type{
        fmt.aprintf(str, ..args, allocator = state.pcl_handle.error_allocator)
    }
}

// exec tree functions /////////////////////////////////////////////////////////

parser_exec_with_childs :: proc(
    state: ^ParserState,
    exec: ExecProc,
    childs: [dynamic]ParseResult,
    flags: bit_set[ExecFlag] = {},
) -> ParseResult {
    pr: ParseResult

    // fmt.printfln("rec depth = {}, branch depth = {}", state.pcl_handle.rd.depth, state.pcl_handle.branch_depth)
    if state.pcl_handle.rd.depth == 0 && state.pcl_handle.branch_depth == 0 {
        if len(childs) == 0 {
            if exec == nil {
                if .ListResult not_in flags {
                    pr = cast(ExecResult)state_string(state)
                } else {
                    pr = cast(ExecResult)make([dynamic]ExecResult, allocator = state.pcl_handle.exec_allocator)
                }
            } else {
                pr = exec(&ExecData{
                    content = []ExecResult{cast(ExecResult)state_string(state)},
                    user_data = state.pcl_handle.user_data,
                    allocator = state.pcl_handle.exec_allocator,
                })
            }
        } else {
            childs_results := make([dynamic]ExecResult, allocator = state.pcl_handle.exec_allocator)

            for child in childs {
                switch c in child {
                case (^ExecTreeNode):
                    if child != nil {
                        append(&childs_results, exec_tree_exec(
                                      c,
                                      state.pcl_handle.user_data,
                                      state.pcl_handle.exec_allocator,
                                      &state.pcl_handle.exec_node_pool,
                                      ))
                    }
                case (ExecResult):
                    append(&childs_results, c)
                }
            }

            if exec == nil {
                if .ListResult not_in flags && len(childs_results) == 1 {
                    pr = childs_results[0]
                    delete(childs_results)
                } else {
                    pr = cast(ExecResult)childs_results
                }
            } else {
                pr = exec(&ExecData{
                    content = childs_results[:],
                    user_data = state.pcl_handle.user_data,
                    allocator = state.pcl_handle.exec_allocator,
                })
                delete(childs_results)
            }
        }
    } else {
        pr = memory_pool_allocate(&state.pcl_handle.exec_node_pool)
        pr.(^ExecTreeNode).ctx = ExecContext{exec, state^}
        pr.(^ExecTreeNode).flags = flags
        pr.(^ExecTreeNode).childs = childs
    }
    return pr
}

parser_exec_with_child :: proc(state: ^ParserState, exec: ExecProc, result: ParseResult, flags: bit_set[ExecFlag] = {}) -> ParseResult {
    results := make([dynamic]ParseResult, allocator = state.pcl_handle.tree_allocator)
    append(&results, result)
    return parser_exec_with_childs(state, exec, results, flags)
}

parser_exec_no_child :: proc(state: ^ParserState, exec: ExecProc, flags: bit_set[ExecFlag] = {}) -> ParseResult {
    return parser_exec_with_childs(state, exec, [dynamic]ParseResult{}, flags)
}

parser_exec :: proc {
    parser_exec_with_childs,
    parser_exec_with_child,
    parser_exec_no_child,
}
