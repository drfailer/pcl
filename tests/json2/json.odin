package json2

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

// parser execute //////////////////////////////////////////////////////////////

ExecData :: struct {
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
    return  proc(data: ^pcl.ExecData) -> pcl.ExecResult {
        ed := pcl.user_data(data, ^ExecData)
        value: JSON_Value
        when type == i32 {
            int_value, ok := strconv.parse_int(pcl.content(data, 0))
            assert(ok)
            value = cast(JSON_Number)(cast(i32)int_value)
        } else {
            f32_value, ok := strconv.parse_f32(pcl.content(data, 0))
            assert(ok)
            value = cast(JSON_Number)f32_value
        }
        add_value(ed, value)
        return nil
    }
}

exec_string :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    ed := pcl.user_data(data, ^ExecData)
    add_value(ed, cast(JSON_String)pcl.content(data, 0))
    return nil
}

exec_entry :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    ed := pcl.user_data(data, ^ExecData)
    append(&ed.object_stack[len(ed.object_stack) - 1].entries, JSON_Entry{
        id = pcl.content(data, 0),
        value = pop(&ed.value_stack),
    })
    return nil
}

exec_list_start :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    ed := pcl.user_data(data, ^ExecData)
    ed.list_count += 1
    append(&ed.value_stack, make(JSON_List, allocator = ed.exec_allocator))
    return nil
}

exec_list_end :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    ed := pcl.user_data(data, ^ExecData)
    ed.list_count -= 1
    if ed.list_count > 0 {
        list := pop(&ed.value_stack)
        append(&ed.value_stack[len(ed.value_stack) - 1].(JSON_List), list)
    }
    return nil
}

exec_object_start :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    ed := pcl.user_data(data, ^ExecData)
    append(&ed.object_stack, JSON_Object{
        entries = make([dynamic]JSON_Entry, allocator = ed.exec_allocator)
    })
    return nil
}

exec_object_end :: proc(data: ^pcl.ExecData) -> pcl.ExecResult {
    ed := pcl.user_data(data, ^ExecData)
    add_value(ed, pop(&ed.object_stack))
    return nil
}

number_grammar :: proc() -> ^pcl.Parser {
    using pcl
    digits := plus(range('0', '9', skip = nil), skip = nil, name = "digits")
    ints := combine(digits, name = "ints", exec = exec_number(i32))
    floats := combine(seq(digits, lit('.'), opt(digits)), skip = nil, name = "floats", exec = exec_number(f32))
    return or(floats, ints)
}

json_grammar :: proc(allocator: pcl.ParserAllocator) -> ^pcl.Parser {
    using pcl

    context.allocator = allocator

    pcl.SKIP = proc(char: rune) -> bool { return u8(char) == ' ' || u8(char) == '\n' }

    json_object := declare(name = "json_object")

    value      := declare(name = "value")
    values     := seq(star(value, ','), value)
    number     := single(number_grammar())
    jstring    := block("\"", "\"", exec = exec_string)
    list_start := lit('[', exec = exec_list_start)
    list_end   := lit(']', exec = exec_list_end)
    list       := seq(list_start, opt(values), list_end, name = "list")
    define(value, or(list, number, jstring, json_object))

    id           := block("\"", "\"")
    entry        := seq(id, ':', value, name = "entry", exec = exec_entry)
    entries      := seq(star(entry, ','), entry)
    object_start := lit('{', exec = exec_object_start)
    object_end   := lit('}', exec = exec_object_end)
    define(json_object, seq(object_start, opt(entries), object_end, name = "object"))
    return json_object
}

@(test)
test_object :: proc(t: ^testing.T) {
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
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

    state, result, ok := pcl.parse_string(json_parser, `{
        "number": 4,
        "string": "Hellope",
        "empty_object": {},
        "object": {
            "pi": 3.14
        },
        "empty_list": [],
        "list": [1, 2, 3, 4]
    }`, &exec_data)
    object := exec_data.value_stack[0].(JSON_Object)

    testing.expect(t, ok == true)
    testing.expect(t, len(object.entries) == 6)

    testing.expect(t, object.entries[0].id == "number")
    testing.expect(t, object.entries[0].value.(JSON_Number).(i32) == 4)

    testing.expect(t, object.entries[1].id == "string")
    testing.expect(t, string(object.entries[1].value.(JSON_String)) == "Hellope")

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
    parser_allocator := pcl.parser_allocator_create()
    defer pcl.parser_allocator_destroy(parser_allocator)
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

    state, result, ok := pcl.parse_string(json_parser, `{
        "number": 4,
        "string": "Hellope",
        "emtpy_object": {},
        "object": {
            "pi": 3.14
        },
        "empty_list": [],
        "list": [1, 2, 3, 4]
    }`, &exec_data)
    object := exec_data.value_stack[0]
    fmt.println(object)
}
