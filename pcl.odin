package pcl

import "core:mem"
import "core:fmt"
import "core:os"
import "core:time"

PCLHandle :: struct {
    branch_depth: u64,
    lrec_depth: u64,
    do_not_exec: bool,
    // parser allocator
    parser_arena: mem.Dynamic_Arena,
    parser_allocator: mem.Allocator,
    // other infos
    user_data: rawptr,
    current_grammar: ^Parser,
}

handle_create :: proc() -> (handle: ^PCLHandle) {
    handle = new(PCLHandle)
    // allocator for the parser graph (optionaly used by the user)
    mem.dynamic_arena_init(&handle.parser_arena)
    handle.parser_allocator = mem.dynamic_arena_allocator(&handle.parser_arena)
    return handle
}

handle_destroy :: proc(handle: ^PCLHandle) {
    mem.dynamic_arena_destroy(&handle.parser_arena)
    free(handle)
}

@(deprecated="the handle does not need to be reset now")
handle_reset :: proc(handle: ^PCLHandle) {
}

handle_grammar :: proc(handle: ^PCLHandle) -> ^Parser {
    return handle.current_grammar
}

handle_parser_allocator :: proc(handle: ^PCLHandle) -> mem.Allocator {
    return handle.parser_allocator
}

// parse api ///////////////////////////////////////////////////////////////////

parse_string :: proc(
    handle: ^PCLHandle,
    parser: ^Parser,
    str: string,
    user_data: rawptr = nil,
) -> bool {
    handle.user_data = user_data
    handle.current_grammar = parser
    global_state := ParserGlobalState{
        content = str,
        handle = handle,
        exec_list = make([dynamic]ExecContext),
    }
    state := state_create(&global_state)
    sw: time.Stopwatch
    defer delete(global_state.exec_list)

    // run the parser and skip trailing (the parse returns an error when the
    // string was not consumed entirely)
    time.stopwatch_start(&sw)
    status := parser_parse(&state, parser)
    parser_skip(&state, parser.skip)
    time.stopwatch_stop(&sw)
    fmt.println("parse time:", time.duration_milliseconds(time.stopwatch_duration(sw)))

    if status != .Success {
        parser_error_report(&state, status)
        return false
    }
    if !state_eof(&state) {
        fmt.printfln("syntax error: the parser did not consume all the string.")
        state_print_context(&state)
        return false
    }
    time.stopwatch_start(&sw)
    exec_run(global_state.exec_list[:], str, user_data)
    time.stopwatch_stop(&sw)
    fmt.println("exec time:", time.duration_milliseconds(time.stopwatch_duration(sw)))
    return true
}

// Since the parser can generate tokens that contain substrings that are just
// slices of the whole parsed string, the lifetime of the file content should
// be extended to the outer scope of this function.
parse_file :: proc(
    handle: ^PCLHandle,
    parser: ^Parser,
    filepath: string,
    user_data: rawptr = nil,
    allocator := context.allocator, // we need to create the string
) -> (filecontent: string, ok: bool) {
	data, err := os.read_entire_file(filepath, allocator)
	if err != nil {
		// could not read file
		return
	}
    filecontent = string(data)
    ok = parse_string(handle, parser, filecontent, user_data)
    return filecontent, ok
}
