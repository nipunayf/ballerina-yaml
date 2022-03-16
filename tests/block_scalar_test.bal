import ballerina/test;

@test:Config {
    dataProvider: blockScalarTokenDataGen
}
function testBlockScalarToken(string line, YAMLToken token, string value) returns error? {
    Lexer lexer = setLexerString(line, LEXER_BLOCK_HEADER);
    check assertToken(lexer, token, lexeme = value);
}

function blockScalarTokenDataGen() returns map<[string, YAMLToken, string]> {
    return {
        "chomping-indicator strip": ["-", CHOMPING_INDICATOR, "-"],
        "chomping-indicator keep": ["+", CHOMPING_INDICATOR, "+"]
    };
}

@test:Config {
    dataProvider: blockScalarEventDataGen
}
function testBlockScalarEvent(string[] lines, string value) returns error? {
    check assertParsingEvent(lines, value);
}

function blockScalarEventDataGen() returns map<[string[], string]> {
    return {
        "correct indentation for indentation-indicator": [["|2", "  value"], "value\n"],
        "ignore trailing comment": [["|-", "  value", "# trailing comment", " #  trailing comment"], " value"]
        // "capture indented comment": [["|-", " # comment", "# trailing comment"], "# comment"],
        // "trailing-lines strip": [["|-", " value", "", " "], "value"],
        // "trailing-lines clip": [["|", " value", "", " "], "value\n"],
        // "trailing-lines keep": [["|+", " value", "", " "], "value\n\n\n"],
        // "empty strip": [["|-", ""], ""],
        // "empty clip": [["|", ""], ""],
        // "empty keep": [["|+", ""], "\n"],
        // "line-break strip": [["|-", " text"], ""],
        // "line-break clip": [["|", " text"], "\n"],
        // "line-break keep": [["|+", " text"], "\n"]
    };
}

@test:Config {
    dataProvider: invalidBlockScalarEventDataGen
}
function testInvalidBlockScalarEvent(string[] lines) returns error? {
    check assertParsingError(lines);
}

function invalidBlockScalarEventDataGen() returns map<[string[]]> {
    return {
        "invalid indentation for indentation-indicator": [["|2", " value"]],
        "leading lines contain less space": [["|2", "  value", " value"]],
        "value after trailing comment": [["|+", " value", "# first comment", "value"]]
    };
}
