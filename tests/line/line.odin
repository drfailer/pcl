package line

import "pcl:pcl"
import "core:fmt"
import "core:log"
import "core:testing"

@(test)
doxygen :: proc(t: ^testing.T) {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    parser: ^pcl.Parser
    results := make([dynamic]string)
    defer delete(results)

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.star(pcl.line_starting_with("///", exec = proc(data: ^pcl.ExecData, content: string) {
            results := pcl.user_data(data, ^[dynamic]string)
            append(results, content)
        }))
    }

    str := `
        /// @brief test
        /// @param foo Foo param.
        /// @return Value.`
    ok := pcl.parse_string(pcl_handle, parser, str, &results)

    testing.expect(t, ok)
    testing.expect(t, len(results) == 3)
    testing.expect(t, results[0] == "/// @brief test\n")
    testing.expect(t, results[1] == "/// @param foo Foo param.\n")
    testing.expect(t, results[2] == "/// @return Value.")
}
