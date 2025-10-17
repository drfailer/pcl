package artihmetic

import "../pcl"
import "core:strconv"
import "core:fmt"
import "core:testing"
import "core:math"

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

node_print_indent :: proc(lvl: int, last_line := false) {
    for i in 0..<lvl {
        fmt.print("|  ")
    }
    if last_line do fmt.print("+---\n")
}

node_print :: proc(node: ^Node, lvl := 0) {
    if node == nil {
        return
    }

    node_print_indent(lvl)
    switch n in node^ {
    case Value:
        switch v in n {
        case i32: fmt.printfln("value: {}", v)
        case f32: fmt.printfln("value: {}", v)
        }
    case Operation:
        fmt.printfln("operator({})", n.kind)
        node_print(n.lhs, lvl + 1)
        node_print(n.rhs, lvl + 1)
        node_print_indent(lvl, true)
    case Parent:
        fmt.println("parent:")
        node_print(n.expr, lvl + 1)
        node_print_indent(lvl, true)
    case Function:
        fmt.printfln("function({}):", n.id)
        node_print(n.expr, lvl + 1)
        node_print_indent(lvl, true)
    }
}

node_eval :: proc(node: ^Node) -> f32 {
    if node == nil {
        return 0
    }

    switch n in node^ {
    case Value:
        switch v in n {
        case i32: return cast(f32)v
        case f32: return v
        }
    case Operation:
        l := node_eval(n.lhs)
        r := node_eval(n.rhs)
        switch n.kind {
        case .Add: return l + r
        case .Sub: return l - r
        case .Mul: return l * r
        case .Div: return l / r
        }
    case Parent:
        return node_eval(n.expr)
    case Function:
        e := node_eval(n.expr)
        switch n.id {
        case .Sin: return math.sin_f32(e)
        case .Cos: return math.cos_f32(e)
        case .Tan: return math.tan_f32(e)
        }
    }
    return 0
}

// exec functions //////////////////////////////////////////////////////////////

exec_value :: proc($type: typeid) -> pcl.ExecProc {
    return  proc(content: []pcl.ParseResult, exec_data: rawptr) -> pcl.ParseResult {
        node := new(Node)
        node^ = cast(Value)(cast(type)strconv.atof(content[0].(string)))
        return cast(rawptr)node
    }
}

exec_operator :: proc($op: Operator) -> pcl.ExecProc {
    return proc(content: []pcl.ParseResult, exec_data: rawptr) -> pcl.ParseResult {
        node := new(Node)
        node^ = Operation{
            kind = op,
            lhs = cast(^Node)content[0].(rawptr),
            rhs = cast(^Node)content[1].(rawptr),
        }
        return cast(rawptr)node
    }
}

exec_function :: proc($id: FunctionId) -> pcl.ExecProc {
    return proc(content: []pcl.ParseResult, exec_data: rawptr) -> pcl.ParseResult {
        node := new(Node)
        node^ = Function{
            id = id,
            expr = cast(^Node)content[0].(rawptr),
        }
        return cast(rawptr)node
    }
}

exec_parent :: proc(content: []pcl.ParseResult, exec_data: rawptr) -> pcl.ParseResult {
    node := new(Node)
    node^ = Parent{
        expr = cast(^Node)content[0].(rawptr),
    }
    return cast(rawptr)node
}

skip_spaces :: proc(char: rune) -> bool {
    return u8(char) == ' ' || u8(char) == '\n'
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
arithmetic_grammar :: proc() -> ^pcl.Parser {
    using pcl

    pcl.SKIP = skip_spaces

    expr := declare(name = "expr")

    digits := plus(range('0', '9'), name = "digits")

    ints := combine(digits, name = "ints", exec = exec_value(i32))
    floats := combine(seq(digits, lit('.'), opt(digits)), name = "floats", exec = exec_value(f32))

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

print_tree_of_expression :: proc(str: string) {
    arithmetic_parser := arithmetic_grammar()
    defer pcl.parser_destroy(arithmetic_parser)

    state, res, ok := pcl.parse_string(arithmetic_parser, str)
    if !ok {
        fmt.printfln("parsing the expression `{}` failed.", str)
        return
    }
    fmt.printfln("tree of `{}`:", str)
    node_print(cast(^Node)res.(rawptr))
}

@(test)
test_numbers :: proc(t: ^testing.T) {
    arithmetic_parser := arithmetic_grammar()
    defer pcl.parser_destroy(arithmetic_parser)

    state, res, ok := pcl.parse_string(arithmetic_parser, "123")
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == 123)

    state, res, ok = pcl.parse_string(arithmetic_parser, "3.14")
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == 3.14)
}

@(test)
test_operation :: proc(t: ^testing.T) {
    arithmetic_parser := arithmetic_grammar()
    defer pcl.parser_destroy(arithmetic_parser)

    state, res, ok := pcl.parse_string(arithmetic_parser, "1 - 2 + 3")
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == (1 - 2 + 3))

    state, res, ok = pcl.parse_string(arithmetic_parser, "(1 - 2) - 3*3 + 4/2")
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == ((1 - 2) - 3*3 + 4/2))
}

@(test)
test_functions :: proc(t: ^testing.T) {
    arithmetic_parser := arithmetic_grammar()
    defer pcl.parser_destroy(arithmetic_parser)

    state, res, ok := pcl.parse_string(arithmetic_parser, "sin(3.14)")
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == math.sin_f32(3.14))

    // BUG: there is an inconsistency when running the sequential parsers when beeing in recusion mode or not
    // state, res, ok = pcl.parse_string(arithmetic_parser, "sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)")
    state, res, ok = pcl.parse_string(arithmetic_parser, "1 + sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)")
    testing.expect(t, ok == true)
    testing.expect(t, node_eval(cast(^Node)res.(rawptr)) == (math.sin_f32(1 - (2 + 3*12.4)) - 3*3 - math.cos_f32(3*4) + 4/2 + (2 + 2)))
}

main :: proc() {
    print_tree_of_expression("123.3")
    print_tree_of_expression("234 + 356 - 123")
    print_tree_of_expression("1 - (2 + 3)")
    print_tree_of_expression("(1 - 2) - 3*3 + 4/2")
    print_tree_of_expression("(1 - (2 + 3*12.4)) - 3*3 + 4/2")
    print_tree_of_expression("(1 - (2 + 3*12.4)) - 3*3 - (3*4) + 4/2 + (2 + 2)")
    print_tree_of_expression("sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)")
}
