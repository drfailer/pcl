package pcl

import "core:mem"
import "base:intrinsics"

/*
 * The purpose of PCL is not to build an AST in which nodes are elements of the
 * grammar. Instead, PCL builds a tree of execution context that allow to call
 * user callback functions during the parsing.
 */

ExecTreeNode :: struct {
    ctx: ExecContext,
    childs: [dynamic]^ExecTreeNode,
}

ExecContext :: struct {
    exec: ExecProc,
    state: ParserState,
}

ExecResult :: union {
    string,              // sub-string of the state
    rawptr,              // user pointer
    [dynamic]ExecResult, // multiple results
}

ExecData :: struct {
    content: []ExecResult,
    user_data: rawptr,
    allocator: mem.Allocator,
}

ExecProc :: proc(data: ^ExecData) -> ExecResult

exec_tree_exec :: proc(root: ^ExecTreeNode, user_data: rawptr) -> ExecResult {
    exec_arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&exec_arena)
    defer mem.dynamic_arena_destroy(&exec_arena)

    exec_data := ExecData{
        user_data = user_data,
        allocator = mem.dynamic_arena_allocator(&exec_arena),
    }

    return exec_tree_node_exec(root, &exec_data)
}

/*
 * cases:
 * - no child & exec nil => return state_string
 * - no child & exec     => return exec(state_string)
 * - childs & exec nil   => return child results
 * - childs & exec       => return exec(childs_results)
 */
exec_tree_node_exec :: proc(node: ^ExecTreeNode, exec_data: ^ExecData) -> ExecResult {
    if len(node.childs) == 0 {
        if node.ctx.exec == nil {
            return state_string(&node.ctx.state)
        }
        exec_data.content = []ExecResult{state_string(&node.ctx.state)}
    } else {
        childs_results := make([dynamic]ExecResult, allocator = exec_data.allocator)

        for child in node.childs {
            if child != nil {
                append(&childs_results, exec_tree_node_exec(child, exec_data))
            }
        }

        if node.ctx.exec == nil {
            if len(childs_results) == 1 {
                return childs_results[0]
            }
            return childs_results
        } else {
            exec_data.content = childs_results[:]
        }
    }
    return node.ctx.exec(exec_data)
}

exec_tree_node_destroy :: proc(node: ^ExecTreeNode) {
    // if node == nil {
    //     return
    // }
    // for &child in node.childs {
    //     exec_tree_node_destroy(child)
    // }
    // delete(node.childs)
    // free(node)
}

// helper function and aliases /////////////////////////////////////////////////////////////

user_data :: proc(data: ^ExecData, $T: typeid) -> T {
    return cast(T)data.user_data
}

content_cast_value :: proc($T: typeid, ptr: rawptr) -> T {
    when intrinsics.type_is_pointer(T) {
        return cast(T)ptr
    } else {
        return (cast(^T)ptr)^
    }
}

content_value_from_result :: proc(result: ExecResult, $T: typeid, indexes: ..int) -> T {
    content := result.([dynamic]ExecResult)[indexes[0]]
    for idx in indexes[1:] {
        content = content.([dynamic]ExecResult)[idx]
    }
    return content_cast_value(T, content.(rawptr))
}

content_value_from_data :: proc(data: ^ExecData, $T: typeid, indexes: ..int) -> T {
    if len(indexes) == 1 {
        return content_cast_value(T, data.content[indexes[0]].(rawptr))
    }
    return content_value_from_result(data.content[indexes[0]], T, ..indexes[1:])
}

content_string_from_result :: proc(result: ExecResult, indexes: ..int) -> string {
    content := result.([dynamic]ExecResult)[indexes[0]]
    for idx in indexes[1:] {
        content = content.([dynamic]ExecResult)[idx]
    }
    return content.(string)
}

content_string_from_data :: proc(data: ^ExecData, indexes: ..int) -> string {
    if len(indexes) == 1 {
        return data.content[indexes[0]].(string)
    }
    return content_string_from_result(data.content[indexes[0]], ..indexes[1:])
}

content :: proc {
    content_value_from_result,
    content_value_from_data,
    content_string_from_result,
    content_string_from_data,
}

contents_from_data :: proc(data: ^ExecData, indexes: ..int) -> [dynamic]ExecResult {
    content := data.content[indexes[0]]
    for idx in indexes[1:] {
        content = content.([dynamic]ExecResult)[idx]
    }
    return content.([dynamic]ExecResult)
}

contents_from_result :: proc(result: ExecResult, indexes: ..int) -> [dynamic]ExecResult {
    content := result.([dynamic]ExecResult)[indexes[0]]
    for idx in indexes[1:] {
        content = content.([dynamic]ExecResult)[idx]
    }
    return content.([dynamic]ExecResult)
}

contents :: proc {
    contents_from_data,
    contents_from_result,
}

result :: proc(data: ^ExecData, value: $T) -> ExecResult {
    when intrinsics.type_is_pointer(T) {
        return cast(rawptr)value
    } else {
        copy := new(T, allocator = data.allocator) // TODO: this allocator is for the nodes, we need a temporary allocator here and we need to be able to free the data
        copy^ = value
        return cast(rawptr)copy
    }
}
