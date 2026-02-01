# Parser Combinator Library (PCL)

This library is a basic parsing DSL that I implemented to learn Odin. The
purpose of this library is not to do any efficient/optimized parsing. The idea
was to try to create a nice interface and explore the Odin's syntax/tools.

Inspirations:
- [mpc](https://github.com/orangeduck/mpc)
- [lexy](https://github.com/foonathan/lexy)

PCL has also been thought to be able to create pre-processing tools for which
all the grammar does not need to be parsed. For this reason, the library allows
creating custom parsers, and each parser has full access to state. This allows
having full control in custom rules to handle special cases (and also write
optimized sub-grammars from scratch if needed). For example, let's say that PCL
is used to create a tool that requires to parse a part of the C syntax, but
without parsing the content of the functions. PCL provides a parser called
`block` which can be used for this purpose: `block('{', '}')` will skip the
content of the function block, and treat it as a string which means that you
don't have to provide any grammar for this. This is a feature that is not
provided by most parsing libraries but that is still useful in a lot of
situations.

## Examples

## Arithmetic expressions

Here is an example of an arithmetic expression grammar (note that the `exec`
functions implementations are not shown here). This grammar uses
left-recursion: the current implementation is unoptimized and I don't guaranty
that it will work in every cases, but it here :D.

```odin
arithmetic_expr_grammar :: proc() -> ^pcl.Parser {
    using pcl

    pcl.SKIP = skip_spaces

    // pre-declare the expression parser (because of the recursion)
    expr := declare(name = "expr")

    // numbers
    digits := plus(range('0', '9'), name = "digits")
    ints := combine(digits, name = "ints", exec = exec_value(i32))
    floats := combine(digits, '.', opt(digits), name = "floats", exec = exec_value(f32))

    // factor
    parent := seq('(', rec(expr), ')', name = "parent", exec = exec_parent)
    sin := seq("sin", parent, exec = exec_function(.Sin))
    cos := seq("cos", parent, exec = exec_function(.Cos))
    tan := seq("tan", parent, exec = exec_function(.Tan))
    functions := or(cos, sin, tan)
    factor := or(floats, ints, parent, functions, name = "factor")

    // term
    term := declare(name = "term")
    mul := lrec(term, '*', factor, exec = exec_operator(.Mul))
    div := lrec(term, '/', factor, exec = exec_operator(.Div))
    define(term, or(mul, div, factor))

    // expression
    add := lrec(expr, '+', term, exec = exec_operator(.Add))
    sub := lrec(expr, '-', term, exec = exec_operator(.Sub))
    define(expr, or(add, sub, term))

    return expr
}
```

Parse a test string:

```odin
// initialize pcl
pcl_handle := pcl.create()
defer pcl.destroy(pcl_handle)
parser := pcl_handle->make_grammar(arithmetic_expr_grammar)

ctx: MyCustomContext

// parse a string
state, res, ok = pcl.parse_string(parser, "sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)", &ctx)
```

## The `exec` functions

An `exec` function can be specified to every combinator to process the result.
If no function is provided, the result of the rule will be a sub-tree created
from the results of the sub-rules. When there are no sub-rules, the result is
automatically set the string parsed by the rule. Note that if there is a single
path leading to a leaf in a sub-tree, the tree is automatically flattened.

The execution function must have the following signature:

```odin
exec :: proc(data: ^pcl.ExecData) -> pcl.ExecResult
```

The data pointer taken as input can be used with different functions:
- `user_data(data, type)`: retrieve the user context.
- `content(data, type, idx..)`: retrieve a result at the give coordinate in the
  sub tree, and cast it to the give type.
- `contents(data, idx..)`: retrieve a list of sub-results at the given
  coordinate in a sub-tree.
- `reuslt(data, value)`: create a result from a value.

Note that the `content` and `result` work with both values and pointers.
However! Since the parser result type is not generic, the underlying
implementation must use a `rawptr`, which means that their will be a hidden
allocation in a dedicated arena in that case (the memory is handled by PCL). If
you don't want to allocate any memory for your AST, you can use an accumulator
in the your custom context (`user_data`).

The `exec` function can also return `nil` if the parser produces no results.

example:

```odin
exec_parent :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    ctx := pcl.user_data(data, ^MyCustomContext) // you can extract the user context from the data
    left_parent := pcl.content(data, ^Node, 0),  // '('
    expr := pcl.content(data, ^Node, 1)          // get the result of the expr rule
    right_parent := pcl.content(data, ^Node, 2), // ')'
    node := new(Node, ctx.allocator)             // in this case we use a pointer for the node
    node^ = Parent{ expr = pcl.content(data, ^Node, 1) }
    return pcl.result(data, node)
}
```

## Extra parser syntax

If you prefer defining the exec functions close to the rule, you can use the
`parser` function:

```odin
// create the rule for type, identifier, argument_list & instruction_block...
function_definition := parser(
    name = "function_definition",
    rule = seq(type, identifier, argument_list, instruction_block),
    exec = proc(data: ^ExecData) -> ExecResult {
        fmt.println("function found:")
        fmt.printfln("return type: {}", content(data, 0))
        fmt.printfln("name: {}", content(data, 1))
        fmt.printfln("arguments: {}", contents(data, 2)) // /!\ we get an array here so we use `contenS`, this may change in the future...
        fmt.printfln("code: {}", content(data, 3))
        return nil // no result
    },
)
```
