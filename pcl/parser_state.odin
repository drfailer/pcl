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
    file: string,
}

// used for left recursive grammars
RecursionData :: struct {
    depth: u64,
    top_nodes: map[^Parser]ParseResult,
}

ParserState :: struct {
    content: ^string,
    pos: int,
    cur: int,
    loc: Location,
    pcl_handle: ^PCLHandle,
}

state_enter_branch :: proc(state: ^ParserState) {
    state.pcl_handle.branch_depth += 1
}

state_leave_branch :: proc(state: ^ParserState) {
    state.pcl_handle.branch_depth -= 1
}

state_set :: proc(dest: ^ParserState, src: ^ParserState) {
    dest.loc = src.loc
    dest.cur = src.cur
}

state_create :: proc(content: ^string, pcl_handle: ^PCLHandle) -> ParserState {
    return ParserState{
        content = content,
        pos = 0,
        cur = 0,
        loc = Location{1, 1, ""},
        pcl_handle = pcl_handle,
    }
}

state_destroy :: proc(state: ^ParserState) {
}

state_eat_one :: proc(state: ^ParserState) -> (ok: bool) {
    if state.cur >= len(state.content^) do return false
    if state_char(state) == '\n' {
        state.loc.row += 1
        state.loc.col = 1
    }
    state.cur += 1
    state.loc.col += 1
    return true
}

state_eof :: proc(state: ^ParserState) -> bool {
    return state.cur >= len(state.content^)
}

state_save_pos :: proc(state: ^ParserState) {
    state.pos = state.cur
}

state_char_at :: proc(state: ^ParserState, idx: int) -> rune {
    assert(idx < len(state.content^)) // top level functions are expected to  check for this beforehand
    return utf8.rune_at_pos(state.content^, idx)
}

state_char :: proc(state: ^ParserState) -> rune {
    return state_char_at(state, state.cur)
}

state_string_at :: proc(state: ^ParserState, begin: int, end: int) -> string {
    if begin == end {
        return ""
    }
    result, ok := strings.substring(state.content^, begin, end)
    assert(ok)
    return result
}

state_string :: proc(state: ^ParserState) -> string {
    return state_string_at(state, state.pos, state.cur)
}

@(private="file")
find_line_start :: proc(state: ^ParserState) -> int {
    idx := state.cur - (state.loc.col - 1)
    if state.content[idx] == '\n' {
        idx += 1
    }
    return idx
}

@(private="file")
find_line_end :: proc(state: ^ParserState) -> int {
    for i := state.cur; i < len(state.content^); i += 1 {
        if state_char_at(state, i) == '\n' do return i
    }
    return len(state.content^)
}

@(private="file")
indent :: proc(n: int) {
    for i := 0; i < n; i += 1 {
        fmt.print(" ")
    }
}

state_print_context :: proc(state: ^ParserState) {
    begin := find_line_start(state)
    end := find_line_end(state)
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
