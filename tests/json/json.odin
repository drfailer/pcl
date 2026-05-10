#+feature using-stmt
package json

/*
 * This second version of the json parser uses the same structure, but the exec
 * functions don't return values. Instead, the ExecData accumulates the values
 * and entries to build the final JSON object. In this test, no allocation is
 * made by pcl (for the values, of course the exec tree is always allocated).
 */

import "pcl:pcl"
import "core:strconv"
import "core:fmt"
import "core:testing"
import "core:math"
import "core:mem"
import "core:log"

// JSON ////////////////////////////////////////////////////////////////////////

JSON_Number :: union { i32, f32 }
JSON_String :: distinct string
JSON_List :: distinct [dynamic]JSON_Value

JSON_Value :: union {
    JSON_Number,
    JSON_String,
    JSON_List,
    JSON_Object,
}

JSON_Entry :: struct {
    id: string,
    value: JSON_Value,
}

JSON_Object :: struct {
    entries: [dynamic]JSON_Entry
}

indent :: proc(lvl: int) {
    for _ in 0..<lvl {
        fmt.print("  ");
    }
}

json_print_value :: proc(jvalue: JSON_Value, lvl: int) {
    switch value in jvalue {
    case (JSON_Number): fmt.print(value)
    case (JSON_String): fmt.print(value)
    case (JSON_List):
        if len(value) == 0 {
            fmt.print("[]")
        } else {
            fmt.println("[")
            for elt in value {
                indent(lvl + 2)
                fmt.printfln("{},", elt);
            }
            indent(lvl + 1)
            fmt.print("]")
        }
        case (JSON_Object):
            if lvl == 0 {
                json_print_object(value, lvl)
                fmt.println()
            } else {
                json_print_object(value, lvl + 1)
            }
    }
}

json_print_object :: proc(json: JSON_Object, lvl: int) {
    if len(json.entries) == 0 {
        fmt.print("{}")
        return
    }
    fmt.println("{");
    for entry in json.entries {
        indent(lvl + 1)
        fmt.printf("\"{}\": ", entry.id);
        json_print_value(entry.value, lvl)
        fmt.printfln(",")
    }
    indent(lvl);
    fmt.print("}");
}

// parser execute //////////////////////////////////////////////////////////////

ExecData :: struct {
    ids: [dynamic]string,
    list_count: int,
    value_stack: [dynamic]JSON_Value,
    object_stack: [dynamic]JSON_Object,
    exec_allocator: mem.Allocator,
}

add_value :: proc(ed: ^ExecData, value: JSON_Value) {
    if ed.list_count > 0 {
        append(&ed.value_stack[len(ed.value_stack) - 1].(JSON_List), value)
    } else {
        append(&ed.value_stack, value)
    }
}

exec_number :: proc($type: typeid) -> pcl.ExecProc {
    return  proc(data: ^pcl.ExecData, content: string) {
        ed := pcl.user_data(data, ^ExecData)
        value: JSON_Value
        when type == i32 {
            int_value, ok := strconv.parse_int(content)
            assert(ok)
            value = cast(JSON_Number)(cast(i32)int_value)
        } else {
            f32_value, ok := strconv.parse_f32(content)
            assert(ok)
            value = cast(JSON_Number)f32_value
        }
        add_value(ed, value)
    }
}

// TODO: we should have a builtin function for this
exec_id :: proc(data: ^pcl.ExecData, content: string) {
    // log.info("id:", content)
    ed := pcl.user_data(data, ^ExecData) // todo should be a stack
    append(&ed.ids, content[1:len(content) - 1])
}

exec_string :: proc(data: ^pcl.ExecData, content: string) {
    // log.info("string:", content)
    ed := pcl.user_data(data, ^ExecData)
    add_value(ed, cast(JSON_String)content)
}

exec_entry :: proc(data: ^pcl.ExecData, content: string) {
    // log.info("entry:", content)
    ed := pcl.user_data(data, ^ExecData)
    append(&ed.object_stack[len(ed.object_stack) - 1].entries, JSON_Entry{
        id = pop(&ed.ids),
        value = pop(&ed.value_stack),
    })
}

exec_list_start :: proc(data: ^pcl.ExecData, content: string) {
    // log.info("list start:", content)
    ed := pcl.user_data(data, ^ExecData)
    ed.list_count += 1
    append(&ed.value_stack, make(JSON_List, allocator = ed.exec_allocator))
}

exec_list_end :: proc(data: ^pcl.ExecData, content: string) {
    // log.info("list end:", content)
    ed := pcl.user_data(data, ^ExecData)
    ed.list_count -= 1
    if ed.list_count > 0 {
        list := pop(&ed.value_stack)
        append(&ed.value_stack[len(ed.value_stack) - 1].(JSON_List), list)
    }
}

exec_object_start :: proc(data: ^pcl.ExecData, content: string) {
    // log.info("obj start:", content)
    ed := pcl.user_data(data, ^ExecData)
    append(&ed.object_stack, JSON_Object{
        entries = make([dynamic]JSON_Entry, allocator = ed.exec_allocator)
    })
}

exec_object_end :: proc(data: ^pcl.ExecData, content: string) {
    // log.info("obj end:", content)
    ed := pcl.user_data(data, ^ExecData)
    add_value(ed, pop(&ed.object_stack))
}

number_grammar :: proc() -> ^pcl.Parser {
    using pcl
    pcl.SKIP = pcl.NO_SKIP
    digits := plus(range('0', '9'), name = "digits")
    ints := combine(digits, exec = exec_number(i32), name = "ints")
    floats := combine(seq(digits, lit('.'), opt(digits)), exec = exec_number(f32), name = "floats")
    return or(floats, ints)
}

json_grammar :: proc(allocator: pcl.ParserAllocator) -> ^pcl.Parser {
    using pcl

    context.allocator = allocator

    number := number_grammar()

    pcl.SKIP = skip_any_of(" \n")

    json_object := declare(name = "json_object")

    value      := declare(name = "value")
    values     := seq(star(value, ','), value)
    jstring    := block("\"", "\"", exec = exec_string)
    list_start := lit('[', exec = exec_list_start)
    list_end   := lit(']', exec = exec_list_end)
    list       := seq(list_start, opt(values), list_end, name = "list")
    define(value, or(list, number, jstring, json_object))

    id           := block("\"", "\"", exec = exec_id)
    entry        := seq(id, ':', value, name = "entry", exec = exec_entry)
    entries      := seq(star(entry, ','), entry)
    object_start := lit('{', exec = exec_object_start)
    object_end   := lit('}', exec = exec_object_end)
    define(json_object, seq(object_start, opt(entries), object_end, name = "object"))
    return json_object
}

@(test)
test_object :: proc(t: ^testing.T) {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    json_parser := json_grammar(parser_allocator)

    exec_arena_data: [16384]byte
    exec_arena: mem.Arena
    mem.arena_init(&exec_arena, exec_arena_data[:])
    exec_allocator := mem.arena_allocator(&exec_arena)
    exec_data := ExecData{
        ids = make([dynamic]string, allocator = exec_allocator),
        value_stack = make([dynamic]JSON_Value, allocator = exec_allocator),
        object_stack = make([dynamic]JSON_Object, allocator = exec_allocator),
        exec_allocator = exec_allocator,
    }

    str := `{
        "number": 4,
        "string": "Hellope",
        "empty_object": {},
        "object": {
            "pi": 3.14
        },
        "empty_list": [],
        "list": [1, 2, 3, 4]
    }`
    ok := pcl.parse_string(pcl_handle, json_parser, str, &exec_data)
    object := exec_data.value_stack[0].(JSON_Object)

    testing.expect(t, ok == true)
    testing.expect(t, len(object.entries) == 6)

    testing.expect(t, object.entries[0].id == "number")
    testing.expect(t, object.entries[0].value.(JSON_Number).(i32) == 4)

    testing.expect(t, object.entries[1].id == "string")
    testing.expect(t, string(object.entries[1].value.(JSON_String)) == "\"Hellope\"")

    testing.expect(t, object.entries[2].id == "empty_object")
    testing.expect(t, len(object.entries[2].value.(JSON_Object).entries) == 0)

    testing.expect(t, object.entries[3].id == "object")
    testing.expect(t, len(object.entries[3].value.(JSON_Object).entries) == 1)
    testing.expect(t, object.entries[3].value.(JSON_Object).entries[0].id == "pi")
    testing.expect(t, object.entries[3].value.(JSON_Object).entries[0].value.(JSON_Number).(f32) == 3.14)

    testing.expect(t, object.entries[4].id == "empty_list")
    testing.expect(t, len(object.entries[4].value.(JSON_List)) == 0)

    testing.expect(t, object.entries[5].id == "list")
    testing.expect(t, len(object.entries[5].value.(JSON_List)) == 4)
    for v, i in object.entries[5].value.(JSON_List) {
        testing.expect(t, v.(JSON_Number).(i32) == i32(i + 1))
    }
}

main :: proc() {
    pcl_handle := pcl.handle_create()
    defer pcl.handle_destroy(pcl_handle)
    parser_allocator := pcl.handle_parser_allocator(pcl_handle)
    json_parser := json_grammar(parser_allocator)

    exec_arena_data: [16384]byte
    exec_arena: mem.Arena
    mem.arena_init(&exec_arena, exec_arena_data[:])
    exec_allocator := mem.arena_allocator(&exec_arena)
    exec_data := ExecData{
        value_stack = make([dynamic]JSON_Value, allocator = exec_allocator),
        object_stack = make([dynamic]JSON_Object, allocator = exec_allocator),
        exec_allocator = exec_allocator,
    }

    str := `{
        "number": 4,
        "string": "Hellope",
        "emtpy_object": {},
        "object": {
            "pi": 3.14
        },
        "empty_list": [],
        "list": [1, 2, 3, 4]
    }`
    ok := pcl.parse_string(pcl_handle, json_parser, str, &exec_data)
    object := exec_data.value_stack[0]
    json_print_value(object, 0)
}
