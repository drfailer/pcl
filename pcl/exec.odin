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

ExecData :: struct {
    exec_ctx: ExecContext,
    user_data: rawptr,
}

ExecProc :: proc(data: ^ExecData, content: string)

// tree execution //////////////////////////////////////////////////////////////

exec_run :: proc(
    exec_list: []ExecContext,
    content: string,
    user_data: rawptr,
) {
    exec_data := ExecData{
        user_data = user_data,
    }
    for ctx in exec_list {
        exec_data.exec_ctx = ctx
        ctx.exec(&exec_data, content[ctx.cursors.pos:ctx.cursors.cur])
    }
}

// helper function and aliases /////////////////////////////////////////////////////////////

user_data :: proc(data: ^ExecData, $T: typeid) -> T {
    return cast(T)data.user_data
}

content_location :: proc(data: ^ExecData) -> Location {
    return data.exec_ctx.cursors.loc
}
