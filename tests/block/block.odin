package block

import "pcl:pcl"
import "core:fmt"
import "core:testing"

skip :: proc(c: rune) -> bool {
    return c == ' ' || c == '\n'
}

@(test)
test_bracket :: proc(t: ^testing.T) {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
    parser: ^pcl.Parser

    {
        context.allocator = parser_allocator
        pcl.SKIP = skip
        parser = pcl.block('{', '}')
    }

    state, result, ok := pcl.parse_string(pcl_handle, parser, `
        {
            printf("}\n");
        }`)

    testing.expect(t, ok)
    testing.expect(t, result.(string) == `
            printf("}\n");
        `)
}

@(test)
test_quotes :: proc(t: ^testing.T) {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
    parser: ^pcl.Parser

    {
        context.allocator = parser_allocator
        pcl.SKIP = skip
        parser = pcl.block('"', '"')
    }

    state, result, ok := pcl.parse_string(pcl_handle, parser, `" printf(\"\"); "`)

    testing.expect(t, ok)
    testing.expect(t, result.(string) == ` printf(\"\"); `)
}

print_bracket :: proc() {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
    parser: ^pcl.Parser

    {
        context.allocator = parser_allocator
        pcl.SKIP = skip
        parser = pcl.block('{', '}')
    }

    state, result, ok := pcl.parse_string(pcl_handle, parser, `
        {
            printf("}\n");
        }`)

    fmt.printfln("result = {}", result)
}

print_quotes :: proc() {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
    parser: ^pcl.Parser

    {
        context.allocator = parser_allocator
        pcl.SKIP = skip
        parser = pcl.block('"', '"')
    }

    state, result, ok := pcl.parse_string(pcl_handle, parser, `" printf(\"\"); "`)

    fmt.printfln("result = {}", result)
}

main :: proc() {
    print_bracket()
    print_quotes()
}
