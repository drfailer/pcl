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

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.block('{', '}')
    }

    str := `
        {
            printf("}\n");
        }`
    result, ok := pcl.parse_string(pcl_handle, parser, &str)

    testing.expect(t, ok)
    testing.expect(t, pcl.content(result) == `
            printf("}\n");
        `)
}

@(test)
test_quotes :: proc(t: ^testing.T) {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    parser: ^pcl.Parser

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.block('"', '"')
    }

    str := `" printf(\"\"); "`
    result, ok := pcl.parse_string(pcl_handle, parser, &str)

    testing.expect(t, ok)
    testing.expect(t, pcl.content(result) == ` printf(\"\"); `)
}

print_bracket :: proc() {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    parser: ^pcl.Parser

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.block('{', '}')
    }
    str := `
        {
            printf("}\n");
        }`
    result, ok := pcl.parse_string(pcl_handle, parser, &str)

    fmt.printfln("result = {}", result)
}

print_quotes :: proc() {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    parser: ^pcl.Parser

    {
        context.allocator = parser_allocator
        pcl.SKIP = pcl.skip_any_of(" \n")
        parser = pcl.block('"', '"')
    }

    str := `" printf(\"\"); "`
    result, ok := pcl.parse_string(pcl_handle, parser, &str)

    fmt.printfln("result = {}", result)
}

main :: proc() {
    print_bracket()
    print_quotes()
}
