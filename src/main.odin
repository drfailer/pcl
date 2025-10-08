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

ExecContext :: struct {
    nodes: [dynamic]Node,
}

create_int_node :: proc(content: string, exec_ctx: rawptr) {
    ctx := cast(^ExecContext)exec_ctx
    append(&ctx.nodes, Node{ name = "int", data = strconv.atoi(content) })
}

create_float_node :: proc(content: string, exec_ctx: rawptr) {
    ctx := cast(^ExecContext)exec_ctx
    append(&ctx.nodes, Node{ name = "float", data = strconv.atof(content) })
}

parse_digits :: proc() -> ^parodin.Parser {
    using parodin
    return plus(range('0', '9'))
}

parse_int :: proc() -> ^parodin.Parser {
    using parodin
    return single(parse_digits(), exec = create_int_node)
}

parse_float :: proc() -> ^parodin.Parser {
    using parodin
    return seq(parse_digits(), lit_c('.'), opt(parse_digits()), exec = create_float_node)
}

parse_number :: proc() -> ^parodin.Parser {
    using parodin
    return or(parse_float(), parse_int(), name = "number")
}

// TODO: print the parser.

test_parser :: proc(name: string, parser: ^parodin.Parser, str: string) {
    ctx: ExecContext
    state, ok := parodin.parse_string(parser, str, exec_ctx = &ctx)
    defer parodin.state_destroy(state)
    defer delete(ctx.nodes)

    fmt.printf("\n{} parser result for input \"{}\":\n", name, str)
    fmt.printf("  ok = {}\n", ok)
    fmt.printf("  state = {}\n", state)
    fmt.printf("  exec_ctx = {}\n", ctx)
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
    ctx: ExecContext
    parser := parse_number()
    defer parodin.parser_destroy(parser)

    state, ok := parodin.parse_string(parser, "1234567890", exec_ctx = &ctx)
    defer parodin.state_destroy(state)
    defer delete(ctx.nodes)
    testing.expect(t, ok)
    testing.expect(t, len(ctx.nodes) == 1)
    node := ctx.nodes[0]
    testing.expect(t, node.name == "int")
    testing.expect(t, node.data == 1234567890)
}

@(test)
test_parse_number_float1 :: proc(t: ^testing.T) {
    ctx: ExecContext
    parser := parse_number()
    defer parodin.parser_destroy(parser)

    state, ok := parodin.parse_string(parser, "1234567890.1234567890", exec_ctx = &ctx)
    defer parodin.state_destroy(state)
    defer delete(ctx.nodes)
    testing.expect(t, ok)
    testing.expect(t, len(ctx.nodes) == 1)
    node := ctx.nodes[0]
    testing.expect(t, node.name == "float")
    testing.expect(t, node.data == 1234567890.1234567890)
}

@(test)
test_parse_number_float2 :: proc(t: ^testing.T) {
    ctx: ExecContext
    parser := parse_number()
    defer parodin.parser_destroy(parser)

    state, ok := parodin.parse_string(parser, "1234567890.", exec_ctx = &ctx)
    defer parodin.state_destroy(state)
    defer delete(ctx.nodes)
    testing.expect(t, ok)
    testing.expect(t, len(ctx.nodes) == 1)
    node := ctx.nodes[0]
    testing.expect(t, node.name == "float")
    testing.expect(t, node.data == 1234567890.0)
}
