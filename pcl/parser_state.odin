package pcl

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import "core:log"
import "core:mem"

// parser state ////////////////////////////////////////////////////////////////

Location :: struct {
    row: int,
    col: int,
    line_start: int,
}

ParserErrorState :: struct {
    parser_name: string,
    location: Location,
    message: string,
}

ParserGlobalState :: struct {
    file: string,
    content: string,
    handle: ^PCLHandle,
    error_state: ParserErrorState,
}

ParserState :: struct {
    global_state: ^ParserGlobalState,
    pos: int,
    cur: int,
    loc: Location,
}

state_create :: proc(global_state: ^ParserGlobalState) -> ParserState {
    return ParserState{
        global_state = global_state,
        pos = 0,
        cur = 0,
        loc = Location{1, 1, 0},
    }
}

state_destroy :: proc(state: ^ParserState) {
}

state_eof :: proc(state: ^ParserState) -> bool {
    return state.cur >= len(state.global_state.content)
}

state_char :: proc(state: ^ParserState) -> rune {
    return state_char_at(state, state.cur)
}

state_char_at :: proc(state: ^ParserState, idx: int) -> rune {
    // TODO: using rune_at_pos is indeed very slow, we'll have to use a rune index at some point
    return cast(rune)state.global_state.content[idx]
}

state_string :: proc(state: ^ParserState) -> string {
    return state_string_at(state, state.pos, state.cur)
}

state_string_at :: proc(state: ^ParserState, begin: int, end: int) -> string {
    if begin >= end {
        return ""
    }
    result, ok := strings.substring(state.global_state.content, begin, end)
    assert(ok)
    return result
}

state_eat :: proc(state: ^ParserState, count: int = 1) -> (ok: bool) {
    if state.cur + count >= len(state.global_state.content) do return false
    for _ in 0..<count {
        if state_char(state) == '\n' {
            state.loc.row += 1
            state.loc.col = 1
            state.loc.line_start = state.cur + 1
        } else {
            state.loc.col += 1
        }
        state.cur += 1
    }
    return true
}

state_eat_unsafe :: proc(state: ^ParserState, count: int = 1) {
    if state_char(state) == '\n' {
        state.loc.row += 1
        state.loc.col = 1
        state.loc.line_start = state.cur + 1
    } else {
        state.loc.col += 1
    }
    state.cur += 1
}

state_eat_non_eol_unsafe :: proc(state: ^ParserState, count: int = 1) {
    state.loc.col += count
    state.cur += count
}

state_pre_exec :: proc(state: ^ParserState, pos, cur: int, loc: Location) {
    state.pos = pos
    state.cur = cur
    state.loc = loc
}

state_post_exec :: proc(state: ^ParserState, loc: Location) {
    state.pos = state.cur
    state.loc = loc
}

state_enter_branch :: proc(state: ^ParserState) {
    state.global_state.handle.branch_depth += 1
}

state_leave_branch :: proc(state: ^ParserState) {
    state.global_state.handle.branch_depth -= 1
}

state_enter_lrec :: proc(state: ^ParserState, parser: ^LRecParser) {
    parser.depth += 1
    state.global_state.handle.lrec_depth += 1
}

state_leave_lrec :: proc(state: ^ParserState, parser: ^LRecParser) {
    parser.depth -= 1
    state.global_state.handle.lrec_depth -= 1
}

@(private="file")
find_line_end :: proc(content: string, begin: int) -> int {
    for i := begin; i < len(content); i += 1 {
        if content[i] == '\n' do return i
    }
    return len(content)
}

@(private="file")
indent :: proc(n: int) {
    for i := 0; i < n; i += 1 {
        fmt.print(" ")
    }
}

state_print_context :: proc(state: ^ParserState) {
    begin := state.loc.line_start
    end := find_line_end(state.global_state.content, begin)
    row_bytes: [10]u8
    sb := strings.builder_from_bytes(row_bytes[:])

    // row to string
    strings.write_int(&sb, state.loc.row)
    row_str := strings.to_string(sb)

    fmt.printfln(" {} | {}", row_str, state_string_at(state, begin, end));
    indent(len(row_str))
    fmt.print("  | ")
    indent(state.cur - begin)
    fmt.print("^\n")
}
