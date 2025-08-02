package main

import "core:fmt"
import "core:strconv"
import "core:log"
import "parodin"

// TODO: move into a different file
import "core:testing"

NodeData :: union {
    int,
    f64,
    string,
}

Node :: struct {
    name: string,
    data: NodeData,
    childs: [dynamic]Node,
}

parse_digits :: proc() -> ^parodin.Parser {
    using parodin
    return plus(range('0', '9'))
}

create_int :: proc(content: string, user_data: rawptr) -> rawptr {
    node := new(Node)
    node.name = "int"
    node.data = strconv.atoi(content)
    return node
}

parse_int :: proc() -> ^parodin.Parser {
    using parodin
    return single(parse_digits(), exec = create_int)
}

create_float :: proc(content: string, user_data: rawptr) -> rawptr {
    node := new(Node)
    node.name = "float"
    node.data = strconv.atof(content)
    return node
}

parse_float :: proc() -> ^parodin.Parser {
    using parodin
    return seq(parse_digits(), lit_c('.'), opt(parse_digits()), exec = create_float)
    // return seq(parse_digits(), lit("."), opt(parse_digits()), exec = create_float)
}

parse_number :: proc() -> ^parodin.Parser {
    using parodin
    return or(parse_float(), parse_int())
}

// TODO: print the parser.

test_parser :: proc(name: string, parser: ^parodin.Parser, str: string,) {
    state, ok := parodin.parse_string(parser, str)
    defer free(state.user_data)

    fmt.printf("\n{} parser result for input \"{}\":\n", name, str)
    fmt.printf("  ok = {}\n", ok)
    fmt.printf("  state = {}\n", state)
    fmt.printf("  user_data = {}\n", (cast(^Node)state.user_data)^)
}

main :: proc() {
    context.logger = log.create_console_logger()

    float_parser := parse_float()
    defer parodin.parser_destroy(float_parser)
    int_parser := parse_int()
    defer parodin.parser_destroy(int_parser)
    number_parser := parse_number()
    defer parodin.parser_destroy(number_parser)

    test_parser("int", int_parser, "1234567890")
    test_parser("int", int_parser, "1234567890.1234567890")
    test_parser("float", float_parser, "1234567890.1234567890")
    test_parser("float", float_parser, "1234567890")
    test_parser("number", number_parser, "1234567890")
    test_parser("number", number_parser, "1234567890.1234567890")
    test_parser("number", number_parser, "1234567890.")
}


@(test)
test_parse_number_int :: proc(t: ^testing.T) {
    node: ^Node
    parser := parse_number()
    defer parodin.parser_destroy(parser)

    state, ok := parodin.parse_string(parser, "1234567890")
    defer free(state.user_data)
    testing.expect(t, ok)
    testing.expect(t, state.user_data != nil)
    node = cast(^Node)state.user_data
    testing.expect(t, node.name == "int")
    testing.expect(t, node.data == 1234567890)
}

@(test)
test_parse_number_float1 :: proc(t: ^testing.T) {
    node: ^Node
    parser := parse_number()
    defer parodin.parser_destroy(parser)

    state, ok := parodin.parse_string(parser, "1234567890.1234567890")
    defer free(state.user_data)
    testing.expect(t, ok)
    testing.expect(t, state.user_data != nil)
    node = cast(^Node)state.user_data
    testing.expect(t, node.name == "float")
    testing.expect(t, node.data == 1234567890.1234567890)
}

@(test)
test_parse_number_float2 :: proc(t: ^testing.T) {
    node: ^Node
    parser := parse_number()
    defer parodin.parser_destroy(parser)

    state, ok := parodin.parse_string(parser, "1234567890.")
    defer free(state.user_data)
    testing.expect(t, ok)
    testing.expect(t, state.user_data != nil)
    node = cast(^Node)state.user_data
    testing.expect(t, node.name == "float")
    testing.expect(t, node.data == 1234567890.0)
}
