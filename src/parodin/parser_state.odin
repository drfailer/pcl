package parodin

ParserState :: struct {
    content: ^string,
    pos: int,
    cur: int,
    user_data: rawptr,
}

state_eat_one :: proc(state: ParserState) -> (new_state: ParserState, ok: bool) {
    if state.cur >= len(state.content^) do return state, false
    new_state = state
    new_state.cur += 1
    return new_state, true
}

state_eof :: proc(state: ParserState) -> bool {
    return state.cur >= len(state.content^)
}

state_save_pos :: proc(state: ^ParserState) {
    state.pos = state.cur
}

state_char :: proc(state: ParserState) -> u8 {
    return state.content[state.cur]
}
