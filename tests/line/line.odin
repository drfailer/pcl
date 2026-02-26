package line

import "pcl:pcl"
import "core:fmt"
import "core:testing"

skip :: proc(c: rune) -> bool {
    return c == ' ' || c == '\n'
}

@(test)
doxygen :: proc(t: ^testing.T) {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
    parser: ^pcl.Parser

    {
        context.allocator = parser_allocator
        pcl.SKIP = skip
        parser = pcl.star(pcl.line_starting_with("///"))
    }

    state, result, ok := pcl.parse_string(pcl_handle, parser, `
        /// @brief test
        /// @param foo Foo param.
        /// @return Value.`)

    testing.expect(t, ok)
    testing.expect(t, len(result.([dynamic]pcl.ExecResult)) == 3)
    testing.expect(t, result.([dynamic]pcl.ExecResult)[0].(string) == "/// @brief test\n")
    testing.expect(t, result.([dynamic]pcl.ExecResult)[1].(string) == "/// @param foo Foo param.\n")
    testing.expect(t, result.([dynamic]pcl.ExecResult)[2].(string) == "/// @return Value.")
}
