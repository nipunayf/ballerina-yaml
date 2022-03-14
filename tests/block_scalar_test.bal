import ballerina/test;

@test:Config {
    dataProvider: blockScalarDataGen
}
function testBlockScalarToken(string line, YAMLToken token, string value) returns error? {
    Lexer lexer = setLexerString(line, LEXER_BLOCK_HEADER);
    check assertToken(lexer, token, lexeme = value);
}

function blockScalarDataGen() returns map<[string, YAMLToken, string]> {
    return {
        "indentation-indicator min": ["1", INDENTATION_INDICATOR, "1"],
        "indentation-indicator max": ["9", INDENTATION_INDICATOR, "9"],
        "chomping-indicator strip": ["-", CHOMPING_INDICATOR, "-"],
        "chomping-indicator keep": ["+", CHOMPING_INDICATOR, "+"]
    };
}
