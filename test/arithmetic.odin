package artihmetic

import "../src/parodin"
import "core:strconv"
import "core:fmt"

Operator :: enum {
    Add,
    Sub,
    Mul,
    Div,
}

Value :: union {
    i32,
    f32,
}

Operation :: struct {
    lhs: Node,
    rhs: Node,
    kind: Operator,
}

Parent :: struct {
    content: Node,
}

FunctionId :: enum {
    Sin,
    Cos,
    Tan,
}

Function :: struct {
    expr: Node,
    kind: FunctionId,
}

Node :: union {
    ^Value,
    ^Operation,
    ^Parent,
}

ExecData :: struct {
    nodes: [dynamic]Node,
    count1: int,
    count2: int,
}

print_indent :: proc(lvl: int) {
    for i in 0..<lvl {
        fmt.print("  ")
    }
}

node_print :: proc(node: Node, lvl: int = 0) {
    switch n in node {
    case ^Value:
        print_indent(lvl)
        switch v in n {
        case i32: fmt.printfln("{}", v)
        case f32: fmt.printfln("{}", v)
        }
    case ^Operation:
        node_print(n.rhs, lvl + 1)
        print_indent(lvl)
        switch n.kind {
        case .Add: fmt.println("+")
        case .Sub: fmt.println("-")
        case .Mul: fmt.println("*")
        case .Div: fmt.println("/")
        }
        node_print(n.lhs, lvl + 1)
    case ^Parent:
        print_indent(lvl)
        fmt.println("(")
        node_print(n.content, lvl + 1)
        print_indent(lvl)
        fmt.println(")")
    }
}

// TODO: create a proper ast and proper tests

exec_ints :: proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
    fmt.printfln("value: {}", content[0].(string))
    // ed := cast(^ExecData)exec_data
    // node := new(Value)
    // node^ = cast(i32)strconv.atoi(content)
    // append(&ed.nodes, node)
    return nil
}

exec_floats :: proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
    fmt.printfln("value: {}", content[0].(string))
    // ed := cast(^ExecData)exec_data
    // node := new(Value)
    // node^ = cast(f32)strconv.atof(content)
    // append(&ed.nodes, node)
    return nil
}

exec_operator :: proc($op: Operator) -> parodin.ExecProc {
    return proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
        fmt.printfln("operator({}): {}", op, content[0].(string))
        // ed := cast(^ExecData)exec_data
        // node := new(Operation)
        // node.kind = op
        // node.rhs = pop(&ed.nodes)
        // node.lhs = pop(&ed.nodes)
        // append(&ed.nodes, node)
        return nil
    }
}

exec_function :: proc($function: FunctionId) -> parodin.ExecProc {
    return proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
        fmt.printfln("function({}): {}", function, content[0].(string))
        // ed := cast(^ExecData)exec_data
        // node := new(Operation)
        // node.kind = op
        // node.rhs = pop(&ed.nodes)
        // node.lhs = pop(&ed.nodes)
        // append(&ed.nodes, node)
        return nil
    }
}

exec_parent :: proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
    fmt.printfln("parent: {}", content[0].(string))
    // ed := cast(^ExecData)exec_data
    // node := new(Parent)
    // node.content = pop(&ed.nodes)
    // append(&ed.nodes, node)
    return nil
}

skip_spaces :: proc(char: rune) -> bool {
    return u8(char) == ' ' || u8(char) == '\n'
}

arithmetic_grammar :: proc() -> ^parodin.Parser {
    using parodin

    parodin.SKIP = skip_spaces

    expr := declare(name = "expr")

    digits := plus(range('0', '9'), name = "digits")

    ints := single(digits, name = "ints", exec = exec_ints)
    floats := seq(digits, lit('.'), opt(digits), name = "floats", exec = exec_floats)
    parent := seq(lit('('), rec(expr), lit(')'), name = "parent", exec = exec_parent)
    sin := seq(lit("sin"), parent, exec = exec_function(.Sin))
    cos := seq(lit("cos"), parent, exec = exec_function(.Cos))
    tan := seq(lit("tan"), parent, exec = exec_function(.Tan))
    functions := or(cos, sin, tan)
    factor := or(floats, ints, parent, functions, name = "factor")

    term := declare(name = "term")
    mul := lrec(term, lit('*'), factor, exec = exec_operator(.Mul))
    div := lrec(term, lit('/'), factor, exec = exec_operator(.Div))
    define(term, or(mul, div, factor))

    add := lrec(expr, lit('+'), term, exec = exec_operator(.Add))
    sub := lrec(expr, lit('-'), term, exec = exec_operator(.Sub))
    define(expr, or(add, sub, term))
    return expr
}

// <expr> := <expr> "+" <term> | <term>
//
// <expr> := <term> <expr'>
// <expr'> := "+" <term> <expr'> | empty
//
// <term> := <factor> <term'>
// <term'> := "*" <factor> <term'> | emtpy
//
// <factor> := <number> | <parent>

main :: proc() {
    ed: ExecData
    arithmetic_parser := arithmetic_grammar()
    defer parodin.parser_destroy(arithmetic_parser)

    // str := "1"
    // str := "1 - (2 + 3)"
    // str := "2 + 3 - 1"
    // str := "(1 - 2) - 3*3 + 4/2"
    // str := "(1 - (2 + 3*12.4)) - 3*3 + 4/2" // missing one operator and one value :(
    // str := "(1 - (2 + 3*12.4)) - 3*3 - (3*4) + 4/2 + (2 + 2)" // the parents on the right cause issues
    str := "sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)" // the parents on the right cause issues
    fmt.println(str)
    state, ok := parodin.parse_string(arithmetic_parser, str, &ed)
    fmt.printfln("{}, {}", state, ok);
    // node_print(ed.nodes[0])
}

// val: 2
// val: 4
// div: 4/2
// val: 3
// val: 3
// mul: 3*3
// val: 2
// val: 1
// sub: 1 - 2
// par: (1 - 2)
// add: (1 - 2) + 3*3
// sub: (1 - 2) + 3*3 - 4/2
