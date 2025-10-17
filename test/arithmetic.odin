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
    lhs: ^Node,
    rhs: ^Node,
    kind: Operator,
}

Parent :: struct {
    expr: ^Node,
}

FunctionId :: enum {
    Sin,
    Cos,
    Tan,
}

Function :: struct {
    id: FunctionId,
    expr: ^Node,
}

Node :: union {
    Value,
    Operation,
    Parent,
    Function,
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

node_print :: proc(node: ^Node, lvl: int = 0) {
    switch n in node^ {
    case Value:
        print_indent(lvl)
        switch v in n {
        case i32: fmt.printfln("{}", v)
        case f32: fmt.printfln("{}", v)
        }
    case Operation:
        node_print(n.rhs, lvl + 1)
        print_indent(lvl)
        switch n.kind {
        case .Add: fmt.println("+")
        case .Sub: fmt.println("-")
        case .Mul: fmt.println("*")
        case .Div: fmt.println("/")
        }
        node_print(n.lhs, lvl + 1)
    case Parent:
        print_indent(lvl)
        fmt.println("(")
        node_print(n.expr, lvl + 1)
        print_indent(lvl)
        fmt.println(")")
    case Function:
        print_indent(lvl)
        fmt.printfln("{}", n.id)
        node_print(n.expr, lvl + 1)
    }
}

// TODO: create a proper ast and proper tests

exec_value :: proc($type: typeid) -> parodin.ExecProc {
    return  proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
        node := new(Node)
        node^ = cast(Value)(cast(type)strconv.atof(content[0].(string)))
        return cast(rawptr)node
    }
}

exec_operator :: proc($op: Operator) -> parodin.ExecProc {
    return proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
        node := new(Node)
        node^ = Operation{
            kind = op,
            lhs = cast(^Node)content[0].(rawptr),
            rhs = cast(^Node)content[1].(rawptr),
        }
        return cast(rawptr)node
    }
}

exec_function :: proc($id: FunctionId) -> parodin.ExecProc {
    return proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
        node := new(Node)
        node^ = Function{
            id = id,
            expr = cast(^Node)content[0].(rawptr),
        }
        return cast(rawptr)node
    }
}

exec_parent :: proc(content: []parodin.ParseResult, exec_data: rawptr) -> parodin.ParseResult {
    node := new(Node)
    node^ = Parent{
        expr = cast(^Node)content[0].(rawptr),
    }
    return cast(rawptr)node
}

skip_spaces :: proc(char: rune) -> bool {
    return u8(char) == ' ' || u8(char) == '\n'
}

arithmetic_grammar :: proc() -> ^parodin.Parser {
    using parodin

    parodin.SKIP = skip_spaces

    expr := declare(name = "expr")

    digits := plus(range('0', '9'), name = "digits")

    ints := single(digits, name = "ints", exec = exec_value(i32))
    floats := seq(digits, lit('.'), opt(digits), name = "floats", exec = exec_value(f32))
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
    state, res, ok := parodin.parse_string(arithmetic_parser, str, &ed)
    fmt.printfln("{}, {}", state, ok);
    node_print(cast(^Node)res.(rawptr))
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
