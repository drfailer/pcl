package pcl

import "core:strings"
import "core:log"
import "core:fmt"

SkipProc :: proc(state: ^ParserState, data: rawptr) -> bool

SkipCtx :: struct {
    skip: SkipProc,
    data: rawptr,
}

NO_SKIP :: SkipCtx{nil, nil}

// allow to define the default skip proc for a set of rules when creating a
// grammar
SKIP: SkipCtx = NO_SKIP

// skip proc constructors //////////////////////////////////////////////////////

skip_any_of :: proc($chars: string) -> SkipCtx {
    return SkipCtx{
        skip = proc(state: ^ParserState, data: rawptr) -> bool {
            if strings.contains_rune(chars, state_char(state)) {
                state_eat_one(state) or_return
                return true
            }
            return false
        },
        data = nil,
    }
}
