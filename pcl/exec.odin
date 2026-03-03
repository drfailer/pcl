package pcl

import "core:mem"
import "core:fmt"
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

ExecResultData :: union {
    string,              // sub-string of the state
    rawptr,              // user pointer
    uint,                // register value
    [dynamic]ExecResult, // multiple results
}

ExecResult :: struct {
    data: ExecResultData,
    loc: Location,
}

ExecData :: struct {
    state: ^ParserState,
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
        state = nil,
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
    loc := node.ctx.state.loc
    exec_data.state = &node.ctx.state
    // release the node once the execution is done
    defer memory_pool_release(exec_data.node_pool, node)

    if len(node.childs) == 0 {
        if node.ctx.exec == nil {
            if .ListResult not_in node.flags {
                return ExecResult{state_string(&node.ctx.state), loc}
            } else {
                empty_resutls := make([dynamic]ExecResult, allocator = exec_data.allocator)
                return ExecResult{empty_resutls, loc}
            }
        }
        exec_data.content = []ExecResult{ExecResult{state_string(&node.ctx.state), loc}}
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
            return ExecResult{childs_results, loc}
        } else {
            exec_data.content = childs_results[:]
            result := node.ctx.exec(exec_data)
            delete(childs_results)
            return result
        }
    }
    return node.ctx.exec(exec_data)
}

// helper function and aliases /////////////////////////////////////////////////////////////

user_data :: proc(data: ^ExecData, $T: typeid) -> T {
    return cast(T)data.user_data
}

content_len_from_result :: proc(result: ExecResult) -> int {
    #partial switch r in result.data {
    case ([dynamic]ExecResult): return len(r)
    }
    return 1
}

content_len_from_data :: proc(data: ^ExecData) -> int {
    return len(data.content)
}

content_len :: proc{
    content_len_from_result,
    content_len_from_data,
}

@(private)
content_cast_value :: proc($T: typeid, result: ExecResult, loc := #caller_location) -> (value: T) {
    when intrinsics.type_is_pointer(T) {
        ptr, ok := result.data.(rawptr)
        if !ok {
            fmt.println(loc, "error: cannot create pointer value.")
        }
        value = cast(T)ptr
    } else when size_of(T) <= size_of(uint) {
        i, ok := result.data.(uint)
        if !ok {
            fmt.println(loc, "error: cannot create register size value.")
        }
        value = transmute(T)i
    } else {
        ptr, ok := result.data.(rawptr)
        if !ok {
            fmt.println(loc, "error: cannot create value.")
        }
        value = (cast(^T)ptr)^
    }
    return value
}

@(private)
get_result_at_idx_from_result :: proc(result: ExecResult, idx: int, loc := #caller_location) -> ExecResult {
    array := result.data.([dynamic]ExecResult) or_else nil
    if array == nil || idx >= len(array) {
        fmt.println(loc, "error: invalid content position.")
    }
    return array[idx]
}

@(private)
get_result_at_idx_from_data :: proc(data: ^ExecData, idx: int, loc := #caller_location) -> ExecResult {
    if idx >= len(data.content) {
        fmt.println(loc, "error: invalid content position.")
    }
    return data.content[idx]
}


@(private)
get_result_at_idx :: proc{
    get_result_at_idx_from_result,
    get_result_at_idx_from_data,
}

content_value_from_result :: proc(result: ExecResult, $T: typeid, indexes: ..int, loc := #caller_location) -> T {
    if len(indexes) == 0 {
        return content_cast_value(T, result, loc)
    }
    return content_value_from_result(get_result_at_idx(result, indexes[0], loc), T, ..indexes[1:], loc = loc)
}

content_value_from_data :: proc(data: ^ExecData, $T: typeid, indexes: ..int, loc := #caller_location) -> T {
    if len(indexes) == 0 {
        return content_cast_value(T, data.content[0], loc)
    }
    return content_value_from_result(get_result_at_idx(data, indexes[0], loc), T, ..indexes[1:], loc = loc)
}

content_string_from_result :: proc(result: ExecResult, indexes: ..int, loc := #caller_location) -> string {
    if len(indexes) == 0 {
         #partial switch r in result.data {
         case string: return r
         case:
             fmt.println(loc, "error: `content` used on an non string content.")
             return ""
         }
    }
    return content_string_from_result(get_result_at_idx(result, indexes[0], loc), ..indexes[1:], loc = loc)
}

content_string_from_data :: proc(data: ^ExecData, indexes: ..int, loc := #caller_location) -> string {
    if len(indexes) == 0 {
        return data.content[0].data.(string)
    }
    return content_string_from_result(get_result_at_idx(data, indexes[0], loc), ..indexes[1:])
}

content :: proc {
    content_value_from_result,
    content_value_from_data,
    content_string_from_result,
    content_string_from_data,
}

contents_from_result :: proc(result: ExecResult, indexes: ..int, loc := #caller_location) -> []ExecResult {
    if len(indexes) == 0 {
        #partial switch r in result.data {
        case ([dynamic]ExecResult): return r[:]
        case:
            fmt.println(loc, "error: `contents` used on an non array content.")
            return nil
        }
    }
    return contents_from_result(get_result_at_idx(result, indexes[0], loc), ..indexes[1:])
}

contents_from_data :: proc(data: ^ExecData, indexes: ..int, loc := #caller_location) -> []ExecResult {
    if len(indexes) == 0 {
        return data.content
    }
    results := contents_from_result(get_result_at_idx(data, indexes[0], loc), ..indexes[1:], loc = loc)
    return results
}


contents :: proc {
    contents_from_data,
    contents_from_result,
}

result_has_content :: proc(result: ExecResult, indexes: ..int, loc := #caller_location) -> bool {
    if len(indexes) == 0 {
        switch data in result.data {
        case string: return data != ""
        case rawptr: return data != nil
        case uint: return true
        case [dynamic]ExecResult: return len(data) > 0
        }
        return false
    }
    return result_has_content(get_result_at_idx(result, indexes[0], loc), ..indexes[1:])
}

data_has_content :: proc(data: ^ExecData, indexes: ..int, loc := #caller_location) -> bool {
    if len(indexes) == 0 {
        return result_has_content(data.content[0])
    }
    return result_has_content(get_result_at_idx(data, indexes[0], loc), ..indexes[1:], loc = loc)
}

has_content :: proc {
    data_has_content,
    result_has_content,
}

content_location_from_result :: proc(result: ExecResult, indexes: ..int, loc := #caller_location) -> Location {
    if len(indexes) == 0 {
        return result.loc
    }
    return content_location_from_result(get_result_at_idx(result, indexes[0], loc), ..indexes[1:], loc = loc)
}

content_location_from_data :: proc(data: ^ExecData, indexes: ..int, loc := #caller_location) -> Location {
    if len(indexes) == 0 {
        return content_location_from_result(data.content[0])
    }
    return content_location_from_result(get_result_at_idx(data, indexes[0], loc), ..indexes[1:], loc = loc)
}

content_location :: proc {
    content_location_from_data,
    content_location_from_result,
}

result :: proc(data: ^ExecData, value: $T) -> ExecResult {
    when intrinsics.type_is_pointer(T) {
        return ExecResult{cast(rawptr)value, data.state.loc}
    } else when size_of(T) <= size_of(uint) {
        return ExecResult{transmute(uint)value, data.state.loc}
    } else {
        copy := new(T, allocator = data.allocator) // TODO: this allocator is for the nodes, we need a temporary allocator here and we need to be able to free the data
        copy^ = value
        return ExecResult{cast(rawptr)copy, data.state.loc}
    }
}

no_result :: proc(data: ^ExecData) -> ExecResult {
    return ExecResult{cast(rawptr)nil, data.state.loc}
}

result_print :: proc(result: ExecResult) {
    switch data in result.data {
    case (string): fmt.printf("\"{}\" ", data)
    case (rawptr): fmt.print(data)
    case (uint): fmt.printf("val:{} ", data)
    case ([dynamic]ExecResult):
        fmt.print("[ ")
        for sub_result in data {
            result_print(sub_result)
            fmt.print(" ")
        }
        fmt.print("]")
    }
}

content_print :: proc(data: ^ExecData) {
    for result in data.content {
        result_print(result)
    }
}
