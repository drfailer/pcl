package pcl

import "core:mem"
import "base:intrinsics"

/*
 * The purpose of PCL is not to build an AST in which nodes are elements of the
 * grammar. Instead, PCL builds a tree of execution context that allow to call
 * user callback functions during the parsing. The tree is only built when the
 * parser is in a branch or a left recursive rule.
 */

ExecFlag :: enum {
    ListResult,
}

ExecTreeNode :: struct {
    ctx: ExecContext,
    flags: bit_set[ExecFlag],
    childs: [dynamic]ParseResult,
}

ExecContext :: struct {
    exec: ExecProc,
    state: ParserState,
}

ExecResult :: union {
    string,              // sub-string of the state
    rawptr,              // user pointer
    uint,                // register value
    [dynamic]ExecResult, // multiple results
}

ExecData :: struct {
    content: []ExecResult,
    user_data: rawptr,
    allocator: mem.Allocator,
    node_pool: ^MemoryPool(ExecTreeNode),
}

ExecProc :: proc(data: ^ExecData) -> ExecResult

exec_tree_exec :: proc(
    root: ^ExecTreeNode,
    user_data: rawptr,
    allocator: mem.Allocator,
    node_pool: ^MemoryPool(ExecTreeNode),
) -> ExecResult {
    exec_data := ExecData{
        user_data = user_data,
        allocator = allocator,
        node_pool = node_pool,
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
    // release the node once the execution is done
    defer memory_pool_release(exec_data.node_pool, node)

    if len(node.childs) == 0 {
        if node.ctx.exec == nil {
            return state_string(&node.ctx.state)
        }
        exec_data.content = []ExecResult{state_string(&node.ctx.state)}
    } else {
        childs_results := make([dynamic]ExecResult, allocator = exec_data.allocator)

        for child in node.childs {
            switch c in child {
            case (^ExecTreeNode):
                if child != nil {
                    append(&childs_results, exec_tree_node_exec(c, exec_data))
                }
            case (ExecResult):
                append(&childs_results, c)
            }
        }

        if node.ctx.exec == nil {
            if .ListResult not_in node.flags && len(childs_results) == 1 {
                result := childs_results[0]
                delete(childs_results)
                return result
            }
            return childs_results
        } else {
            exec_data.content = childs_results[:]
            result := node.ctx.exec(exec_data)
            delete(childs_results)
            return result
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

content_cast_value :: proc($T: typeid, result: ExecResult) -> T {
    when intrinsics.type_is_pointer(T) {
        return cast(T)result.(rawptr)
    } else when size_of(T) <= size_of(uint) {
        return transmute(T)result.(uint)
    } else {
        return (cast(^T)result.(rawptr))^
    }
}

content_value_from_result :: proc(result: ExecResult, $T: typeid, indexes: ..int) -> T {
    if len(indexes) == 0 {
        return content_cast_value(T, result)
    }
    content := result.([dynamic]ExecResult)[indexes[0]]
    for idx in indexes[1:] {
        content = content.([dynamic]ExecResult)[idx]
    }
    return content_cast_value(T, content)
}

content_value_from_data :: proc(data: ^ExecData, $T: typeid, indexes: ..int) -> T {
    if len(indexes) == 0 {
        return content_cast_value(T, data.content[0])
    }
    return content_value_from_result(data.content[indexes[0]], T, ..indexes[1:])
}

content_string_from_result :: proc(result: ExecResult, indexes: ..int) -> string {
    if len(indexes) == 0 {
        return result.(string)
    }
    content := result.([dynamic]ExecResult)[indexes[0]]
    for idx in indexes[1:] {
        content = content.([dynamic]ExecResult)[idx]
    }
    return content.(string)
}

content_string_from_data :: proc(data: ^ExecData, indexes: ..int) -> string {
    if len(indexes) == 0 {
        return data.content[0].(string)
    }
    return content_string_from_result(data.content[indexes[0]], ..indexes[1:])
}

content :: proc {
    content_value_from_result,
    content_value_from_data,
    content_string_from_result,
    content_string_from_data,
}

contents_from_result :: proc(result: ExecResult, indexes: ..int) -> ([]ExecResult, bool) {
    if len(indexes) == 0 {
        #partial switch r in result {
        case ([dynamic]ExecResult): return r[:], true
        case: return nil, false
        }
    }
    return contents_from_result(result.([dynamic]ExecResult)[indexes[0]], ..indexes[1:])
}

contents_from_data :: proc(data: ^ExecData, indexes: ..int, loc := #caller_location) -> []ExecResult {
    if len(indexes) == 0 {
        return data.content
    }
    results, ok := contents_from_result(data.content[indexes[0]], ..indexes[1:])
    if !ok {
        fmt.println(loc, "`contents` used on an non array content.")
    }
    return results
}


contents :: proc {
    contents_from_data,
    contents_from_result,
}

result :: proc(data: ^ExecData, value: $T) -> ExecResult {
    when intrinsics.type_is_pointer(T) {
        return cast(rawptr)value
    } else when size_of(T) <= size_of(uint) {
        return transmute(uint)value
    } else {
        copy := new(T, allocator = data.allocator) // TODO: this allocator is for the nodes, we need a temporary allocator here and we need to be able to free the data
        copy^ = value
        return cast(rawptr)copy
    }
}
