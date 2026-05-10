package pcl

import "core:mem"
import "core:fmt"
import "base:intrinsics"

/*
 * The exec tree is too slow, the new objective is to build a simpler exec list
 * and only process the regions of the string that are bound to exec function.
 * This means that we do not collect the tokens anymore, and the result are
 * transmitted between exec procs using a map (easier and more intuitive than
 * the previous method).
 *
 * TLDR: there is no tokenization anymore, we just run the exec on the
 * "executable content", and we don't manage the results anymore and we use an
 * internal map instead (more intuitive and simpler)
 */

ExecContext :: struct {
    exec: ExecProc,
    cursors: ParserStateCursors
}

ParseResult :: union {
    string,
    rawptr,
    uint,
}

ExecData :: struct {
    exec_ctx: ExecContext,
    user_data: rawptr,
    results: map[string][dynamic]ParseResult,
}

ExecProc :: proc(data: ^ExecData, content: string)

// execution //// //////////////////////////////////////////////////////////////

exec_run :: proc(
    exec_list: []ExecContext,
    content: string,
    user_data: rawptr,
) {
    exec_data := ExecData{
        results = make(map[string][dynamic]ParseResult),
        user_data = user_data,
    }
    defer {
        for key, results in exec_data.results {
            delete(results)
        }
        delete(exec_data.results)
    }
    for ctx in exec_list {
        exec_data.exec_ctx = ctx
        ctx.exec(&exec_data, content[ctx.cursors.pos:ctx.cursors.cur])
    }
}

// Exec proc API ///////////////////////////////////////////////////////////////

user_data :: proc(data: ^ExecData, $T: typeid) -> T {
    return cast(T)data.user_data
}

content_location :: proc(data: ^ExecData) -> Location {
    return data.exec_ctx.cursors.loc
}

result_push :: proc(data: ^ExecData, key: string, result: $T, loc := #caller_location) {
    if key not_in data.results {
        data.results[key] = make([dynamic]ParseResult)
    }
    when intrinsics.type_is_pointer(T) {
        append(&data.results[key], transmute(rawptr)result)
    } else when size_of(T) <= size_of(uint) {
        append(&data.results[key], transmute(uint)result)
    } else when intrinsics.type_is_string(T) {
        append(&data.results[key], result)
    } else {
        fmt.println(loc, "error: result can only contain strings, pointers or register sized values.")
    }
}

result_pop :: proc {
    result_pop_type,
    result_pop_string,
}

result_pop_type :: proc(data: ^ExecData, key: string, $T: typeid, loc := #caller_location) -> Maybe(T) {
    if results, ok := &data.results[key]; ok {
        if len(results) == 0 do return nil
        result := results[len(results) - 1]
        when intrinsics.type_is_pointer(T) {
            if ptr, is_ptr := result.(rawptr); is_ptr {
                pop(&data.results[key])
                return transmute(T)ptr
            }
            fmt.println(loc, "error: failed to pop pointer result.")
        } else when size_of(T) <= size_of(uint) {
            if reg_size, is_reg_size := result.(uint); is_reg_size {
                pop(&data.results[key])
                return transmute(T)reg_size
            }
            fmt.println(loc, "error: failed to pop a register sized result.")
        } else when intrinsics.type_is_string(T) {
            if str, is_str := result.(string); is_str {
                pop(&data.results[key])
                return str
            }
            fmt.println(loc, "error: failed to pop string result.")
        } else {
            fmt.println(loc, "error: tried to pop a non supported type, results can only",
                             "contain strings, pointers or register sized values.")
        }
    } else {
        fmt.println(loc, "error: unknown key", key)
    }
    return nil
}

result_pop_string :: proc(data: ^ExecData, key: string, loc := #caller_location) -> Maybe(string) {
    if results, ok := &data.results[key]; ok {
        if len(results) == 0 do return nil
        result := results[len(results) - 1]
        if str, is_str := result.(string); is_str {
            pop(&data.results[key])
            return str
        }
        fmt.println(loc, "error: failed to pop string result.")
    } else {
        fmt.println(loc, "error: unknown key", key)
    }
    return nil
}

results_count :: proc(data: ^ExecData, key: string) -> int {
    if results, ok := data.results[key]; ok {
        return len(results)
    }
    return 0
}

results_clear :: proc(data: ^ExecData, key: string) {
    if results, ok := &data.results[key]; ok {
        clear(results)
    }
}

results_get :: proc(data: ^ExecData, key: string) -> []ParseResult {
    if results, ok := data.results[key]; ok {
        return results[:]
    }
    return []ParseResult{}
}

// Builtin exec proc helpers ///////////////////////////////////////////////////

collect_content_under_key :: proc($key: string) -> ExecProc {
    return proc(data: ^ExecData, content: string) {
        result_push(data, content)
    }
}

