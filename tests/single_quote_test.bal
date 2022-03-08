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

@test:Config {}
function testSeparateInLineAfterPlanar() returns error? {
    Lexer lexer = setLexerString("planar space      ", LEXER_DOCUMENT_OUT);
    check assertToken(lexer, PLANAR_CHAR, lexeme = "planar space");
    check assertToken(lexer, SEPARATION_IN_LINE);
}

@test:Config {}
function testMultilinePlanarEvent() returns error?{
    check assertParsingEvent(["1st non-empty"," "," 2nd non-empty ", "  3rd non-empty"], "1st non-empty\n2nd non-empty 3rd non-empty");
}

@test:Config {
    dataProvider: implicitKeyDataGen
}
function testImplicitKeyEvent(string line, string? key, string? value) returns error? {
    Parser parser = check new Parser([line]);

    Event event = check parser.parse();
    test:assertTrue((<ScalarEvent>event).isKey);
    test:assertEquals((<ScalarEvent>event).value, key);

    event = check parser.parse();
    test:assertEquals((<ScalarEvent>event).value, value);
}

function implicitKeyDataGen() returns map<[string, string?, string?]> {
    return {
        "yaml key": ["unquoted : \"value\"", "unquoted", "value"],
        "omitted value": ["omitted value: ", "omitted value", ()],
        "no key": [": value", (), "value"]
    };
}