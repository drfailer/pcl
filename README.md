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
optimized sub-grammars from scratch if needed).

## Examples

## Arithmetic expressions

Here is an example of an arithmetic expression grammar (note that the `exec`
functions implementations are not shown here). This grammar uses
left-recursion: the current implementation is unoptimized and I don't guaranty
that it will work in every cases, but at least it is here :D.

```odin
arithmetic_expr_grammar :: proc() -> ^pcl.Parser {
    using pcl

    digits := plus(range('0', '9'), name = "digits")
    ints := combine(digits, name = "ints", exec = exec_value(i32))
    floats := combine(digits, '.', opt(digits), name = "floats", exec = exec_value(f32))

    pcl.SKIP = skip_any_of(" \n")

    expr := declare_lrec(name = "expr")

    parent := seq('(', expr, ')', name = "parent", exec = exec_parent)
    sin := seq("sin", parent, exec = exec_function(.Sin))
    cos := seq("cos", parent, exec = exec_function(.Cos))
    tan := seq("tan", parent, exec = exec_function(.Tan))
    functions := or(cos, sin, tan)
    factor := or(floats, ints, parent, functions, name = "factor")

    term := declare_lrec(name = "term")
    mul := lrec(term, '*', factor, exec = exec_operator(.Mul))
    div := lrec(term, '/', factor, exec = exec_operator(.Div))
    define(term, or(mul, div, factor))

    // lrec accepts "middle rules" that can optionaly be used to implement operators
    add := lrec(expr, '+', term, exec = exec_operator(.Add))
    sub := lrec(expr, '-', term, exec = exec_operator(.Sub))
    define(expr, or(add, sub, term))
    return expr
}
```

Parse a test string:

```odin
pcl_handle := pcl.handle_create()
defer pcl.handle_destroy(pcl_handle)
{
    // the parser structure is non trivial, therefore, PCL consider that it
    // belongs to the user. The handle can provide an optional allocator to
    // avoid delete the grammar by hand.
    context.allocator pcl.handle_parser_allocator(handle)
    arithmetic_parser := arithmetic_grammar()
}

ctx: MyCustomContext

// parse a string
ok = pcl.parse_string(pcl_handle, parser, "sin(1 - (2 + 3*12.4)) - 3*3 - cos(3*4) + 4/2 + (2 + 2)", &ctx)
assert(ok, "the parser failed :(")
node_print(ctx.nodes[0])
```

## Parser allocation

The parser is stored as a graph in which each node contains a parse function,
and a list of sub-parsers. The parser graph can contain cycles and custom nodes
that are define by the user (custom parsers). For these reasons, the parser
graph is considered as a user property, therefore, the user is responsible to
deallocate the nodes of the graph. This has been done for simplicity reasons
because:
1. Handling cycles would require extra work for the deallocation.
2. Users can create their own parsers, and handling the deallocation would
   imply adding an `on_destroy` callback.
Even though the user is responsible to deallocate the parsers, PCL provides an
arena that can be used to allocate parsers if needed (which still requires to
set the context allocator, so the user keep full control).

```odin
parser_allocator := pcl.handle_parser_allocator(handle)
```

## The `exec` functions

PCL goal is to be very simple, therefore, it does not provide any automatic AST
builder of any kind. This is done firstly because it doesn't always make sense
(you don't always wan't an AST), and it let users free of choosing the AST
implementation if one is required (union/fat-struct, pointers/indices, ...).

PCL relies on `exec` callbacks that have the follwing signature:

```odin
exec :: proc(data: ^pcl.ExecData, content: string)
```

- `data` is a handle that can be used the following ways:
  - `pcl.user_data(data, ^ContextType)`: get you context (pointer passed to the
    parse functions).
  - `pcl.location(data)`: get the location of the content (`{row, col, file}`).
- `content`: string parse by the rule.

### Example

```odin
identifier_exec :: proc(data: ^pcl.ExecData, content: string) {
    ctx := plc.user_data(data, ^ParserContext)
    ctx.last_identifier = content
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
    exec = proc(data: ^ExecData, content: string) {
        ctx := pcl.user_data(data, ^MyContextType)
        // do stuff...
    },
)
```
