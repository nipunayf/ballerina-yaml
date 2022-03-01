import ballerina/test;

@test:Config {
    dataProvider: singleQuoteDataGen
}
function testSingleQuoteEvent(string[] arr, string value) returns error? {
    check assertParsingEvent(arr, value);
}

function singleQuoteDataGen() returns map<[string[], string]> {
    return {
        "empty": [["''"], ""],
        "single-quote": [["''''"], "'"],
        "double-quote": [["''''''"], "''"],
        "multi-line": [["' 1st non-empty",""," 2nd non-empty ","3rd non-empty '"], " 1st non-empty\n2nd non-empty 3rd non-empty "]
    };
}

@test:Config {
    dataProvider: planarDataGen
}
function testPlanarToken(string line, string lexeme) returns error? {
    Lexer lexer = setLexerString(line, LEXER_DOCUMENT_OUT);
    check assertToken(lexer, PLANAR_CHAR, lexeme = lexeme);
}

function planarDataGen() returns map<[string, string]> {
    return {
        "ns-char": ["ns", "ns"],
        ":": ["::", "::"],
        "?": ["??", "??"],
        "-": ["--", "--"],
        "ignore-comment": ["plain #comment", "plain"],
        "#": ["plain#comment", "plain#comment"],
        "space": ["plain space", "plain space"]
    };
}