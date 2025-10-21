package pcl

import "core:mem"

/*
 * The purpose of PCL is not to build an AST in which nodes are elements of the
 * grammar. Instead, PCL builds a tree of execution context that allow to call
 * user callback functions during the parsing.
 */

ExecContext :: struct {
    exec: ExecProc,
    state: ParserState,
}

ExecTreeNode :: struct {
    ctx: ExecContext,
    childs: [dynamic]^ExecTreeNode,
}

/*
 * cases:
 * - no child & exec nil => return state_string
 * - no child & exec     => return exec(state_string)
 * - childs & exec nil   => return child results
 * - childs & exec       => return exec(childs_results)
 */
exec_tree_node_execute :: proc(node: ^ExecTreeNode, allocator: mem.Allocator) -> ExecResult {
    if len(node.childs) == 0 {
        if node.ctx.exec == nil {
            return state_string(&node.ctx.state)
        } else {
            return node.ctx.exec([]ExecResult{state_string(&node.ctx.state)}, node.ctx.state.global_state.exec_data)
        }
    } else {
        childs_results := make([dynamic]ExecResult, allocator = allocator)

        for child in node.childs {
            append(&childs_results, exec_tree_node_execute(child, allocator))
        }

        if node.ctx.exec == nil {
            if len(childs_results) == 1 {
                return childs_results[0]
            }
            return childs_results
        } else {
            return node.ctx.exec(childs_results[:], node.ctx.state.global_state.exec_data)
        }
    }
    return nil
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
