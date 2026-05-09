package block

import "pcl:pcl"
import "core:fmt"
import "core:testing"

@(test)
test_bracket :: proc(t: ^testing.T) {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    parser: ^pcl.Parser
    result := ""

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.block('{', '}', exec = proc(data: ^pcl.ExecData, content: string) {
            result := pcl.user_data(data, ^string)
            result^ = content
        })
    }

    str := `
        {
            printf("}\n");
        }`
    ok := pcl.parse_string(pcl_handle, parser, str, &result)

    testing.expect(t, ok)
    testing.expect(t, result == `{
            printf("}\n");
        }`)
}

@(test)
test_quotes :: proc(t: ^testing.T) {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    parser: ^pcl.Parser
    result := ""

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.block('"', '"', exec = proc(data: ^pcl.ExecData, content: string) {
            result := pcl.user_data(data, ^string)
            result^ = content
        })
    }

    str := `" printf(\"\"); "`
    ok := pcl.parse_string(pcl_handle, parser, str, &result)

    testing.expect(t, ok)
    testing.expect(t, result == `" printf(\"\"); "`)
}

print_bracket :: proc() {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    parser: ^pcl.Parser
    result := ""

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.block('{', '}', exec = proc(data: ^pcl.ExecData, content: string) {
            result := pcl.user_data(data, ^string)
            result^ = content
        })
    }
    str := `
        {
            printf("}\n");
        }`
    ok := pcl.parse_string(pcl_handle, parser, str, &result)

    fmt.printfln("result = {}", result)
}

print_quotes :: proc() {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    parser: ^pcl.Parser
    result := ""

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.block('"', '"', exec = proc(data: ^pcl.ExecData, content: string) {
            result := pcl.user_data(data, ^string)
            result^ = content
        })
    }

    str := `" printf(\"\"); "`
    ok := pcl.parse_string(pcl_handle, parser, str, &result)

    fmt.printfln("result = {}", result)
}

main :: proc() {
    print_bracket()
    print_quotes()
}
