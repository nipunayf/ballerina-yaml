import ballerina/test;

@test:Config {
    dataProvider: escapedCharacterDataGen,
    groups: ["escaped"]
}
function testEscapedCharacterToken(string lexeme, string value) returns error? {
    Lexer lexer = setLexerString("\\" + lexeme, LEXER_DOUBLE_QUOTE);
    check assertToken(lexer, DOUBLE_QUOTE_CHAR, lexeme = value);
}

function escapedCharacterDataGen() returns map<[string, string]> {
    return {
        "null": ["0", "\u{00}"],
        "bell": ["a", "\u{07}"],
        "backspace": ["b", "\u{08}"],
        "horizontal-tab": ["t", "\t"],
        "line-feed": ["n", "\n"],
        "vertical-tab": ["v", "\u{0b}"],
        "form-feed": ["f", "\u{0c}"],
        "carriage-return": ["r", "\r"],
        "escape": ["e", "\u{1b}"],
        "double-quote": ["\"", "\""],
        "slash": ["/", "/"],
        "backslash": ["\\", "\\"],
        "next-line": ["N", "\u{85}"],
        "non-breaking-space": ["_", "\u{a0}"],
        "line-separator": ["L", "\u{2028}"],
        "paragraph-separator": ["P", "\u{2029}"],
        "space": [" ", " "],
        "x-2": ["x41", "A"],
        "u-4": ["0041", "A"],
        "U-8": ["00000041", "A"]
    };
}

@test:Config {
    dataProvider: invalidEscapedCharDataGen,
    groups: ["escaped"]
}
function testInvalidExcapedCharacter(string lexeme) {
    assertLexicalError("\\" + lexeme, state = LEXER_DOUBLE_QUOTE);
}

function invalidEscapedCharDataGen() returns map<[string]> {
    return {
        "x-1": ["x1"],
        "x-3": ["x333"],
        "u-3": ["u333"],
        "u-5": ["u55555"],
        "U-7": ["u7777777"],
        "U-9": ["u999999999"],
        "no-char": [""],
        "invalid-char": ["z"]
    };
}
