package pcl

ExecResult :: union {
    string,              // sub-string of the state
    rawptr,              // user pointer
    [dynamic]ExecResult, // multiple results
}

// some aliases

ParseResult :: ^ExecTreeNode
ExecData :: rawptr

ER :: ExecResult
EC :: []ExecResult
ED :: ExecData

ExecProc :: proc(c: EC, d: ED) -> ExecResult

PredProc :: proc(c: rune) -> bool // TODO: should it take the state?

ParseProc :: proc(self: ^Parser, state: ^ParserState) -> (res: ParseResult, err: ParserError)

ParserData :: union {
    PredProc,
}

// helper functions to unpack the exec content

ec_type :: proc($T: typeid, c: EC, idx: int) -> T {
    return cast(T)c[idx].(rawptr)
}

ec_string :: proc(c: EC, idx: int) -> string {
    return c[idx].(string)
}

ec :: proc {
    ec_type,
    ec_string,
}
