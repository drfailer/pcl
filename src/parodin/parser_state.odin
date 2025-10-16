package parodin

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import "core:log"

Location :: struct {
    row: int,
    col: int,
    file: string,
}

// TODO: add a max recursion depth in the state

ExecContext :: struct {
    exec: ExecProc,
    state: ParserState,
}

ExecTree :: struct {
    lhs: ^ExecTree,
    rhs: ^ExecTree,
    execs: [dynamic]ExecContext,
}

exec_tree_exec :: proc(tree: ^ExecTree, lvl := 0) {
    if tree == nil {
        return
    }

    #reverse for &ctx in tree.execs {
        for j in 0..<lvl {
            fmt.print("|  ")
        }
        parser_exec(&ctx)
    }
    exec_tree_exec(tree.lhs, lvl + 1)
    exec_tree_exec(tree.rhs, lvl + 1)
    if tree.lhs != nil || tree.rhs != nil {
        for i in 0..<lvl {
            fmt.print("|  ")
        }
        fmt.print("+---\n")
    }
}

RecursionData :: struct {
    exec_trees: map[^Parser]^ExecTree,
    current_node: ^ExecTree,
    depth: u64, // depth per recursive rules???
}

ParserState :: struct {
    content: ^string,
    pos: int,
    cur: int,
    loc: Location,
    exec_data: rawptr,
    rd: RecursionData,
}

state_set :: proc(dest: ^ParserState, src: ^ParserState) {
    dest.cur = src.cur
    dest.rd = src.rd
}

state_create :: proc(content: ^string, exec_data: rawptr) -> ParserState {
    return ParserState{
        content = content,
        pos = 0,
        cur = 0,
        loc = Location{1, 1, ""},
        exec_data = exec_data,
    }
}

state_destroy :: proc(state: ParserState) {
}

state_eat_one :: proc(state: ^ParserState) -> (ok: bool) {
    if state.cur >= len(state.content^) do return false
    if state_char(state) == '\n' {
        state.loc.row += 1
        state.loc.col = 0
    }
    state.cur += 1
    state.loc.col += 1
    return true
}

state_advance :: proc(state: ^ParserState) -> (ok: bool) {
    if state.cur >= len(state.content^) do return false
    state.cur += 1
    state.pos += 1
    return true
}

state_eof :: proc(state: ^ParserState) -> bool {
    return state.cur >= len(state.content^)
}

state_save_pos :: proc(state: ^ParserState) {
    state.pos = state.cur
}

state_char_at :: proc(state: ^ParserState, idx: int) -> rune {
    return utf8.rune_at_pos(state.content^, idx)
}

state_char :: proc(state: ^ParserState) -> rune {
    return state_char_at(state, state.cur)
}

state_string_at :: proc(state: ^ParserState, begin: int, end: int) -> string {
    // TODO: how to deal with an error here?
    result, _ := strings.substring(state.content^, begin, end)
    return result
}

state_string :: proc(state: ^ParserState) -> string {
    return state_string_at(state, state.pos, state.cur)
}

state_cursor_on_string :: proc(state: ^ParserState, $prefix: string) -> bool {
    state_idx := state.cur
    for c in prefix {
        if state_idx > len(state.content) || state.content[state_idx] != c {
            return false
        }
        state_idx += 1
    }
    return true
}

@(private="file")
find_line_start :: proc(state: ^ParserState) -> int {
    cur := min(state.cur, len(state.content^) - 1)
    for i := cur; i >= 0; i -= 1 {
        if state_char_at(state, i) == '\n' do return i
    }
    return 0
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
