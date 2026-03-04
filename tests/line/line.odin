package line

import "pcl:pcl"
import "core:fmt"
import "core:log"
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

    str := `
        /// @brief test
        /// @param foo Foo param.
        /// @return Value.`
    state, result, ok := pcl.parse_string(pcl_handle, parser, &str)

    testing.expect(t, ok)
    testing.expect(t, pcl.content_len(result) == 3)
    testing.expect(t, pcl.content(result, 0) == "/// @brief test\n")
    testing.expect(t, pcl.content(result, 1) == "/// @param foo Foo param.\n")
    testing.expect(t, pcl.content(result, 2) == "/// @return Value.")
}
