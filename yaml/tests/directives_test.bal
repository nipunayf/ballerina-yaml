import ballerina/test;

@test:Config {
    dataProvider: directiveDataGen,
    groups: ["directives"]
}
function testDirectivesToken(string lexeme, string value) returns error? {
    Lexer lexer = setLexerString(lexeme);
    check assertToken(lexer, DIRECTIVE, lexeme = value);
}

function directiveDataGen() returns map<[string, string]> {
    return {
        "yaml-directive": ["%YAML", "YAML"],
        "tag-directive": ["%TAG", "TAG"]
    };
}

@test:Config {
    groups: ["directives"]
}
function testAccurateYAMLDirective() returns error? {
    Parser parser = new Parser(["%YAML 1.3"]);
    check parser.parse();

    test:assertEquals(parser.yamlVersion, "1.3");
}

@test:Config {
    groups: ["directives"]
}
function testDuplicateYAMLDirectives() {
    Parser parser = new Parser(["%YAML 1.3", "%YAML 1.1"]);
    error? parseErr = parser.parse();

    test:assertTrue(parseErr is ParsingError);
}

@test:Config {
    dataProvider: invalidDirectiveDataGen,
    groups: ["directives"]
}
function testInvalidYAMLDirectives(string yam) {
    Parser parser = new Parser([yam]);
    error? parseErr = parser.parse();

    test:assertTrue(parseErr is ParsingError);
}

function invalidDirectiveDataGen() returns map<[string]> {
    return {
        "additional dot" : ["%YAML 1.2.1"],
        "no space": ["%YAML1.2"],
        "single digit" : ["%YAML 1"]
    };
}

@test:Config {
    dataProvider: validTagDataGen
}
function testValidTagHandlers(string tag, string lexeme) returns error? {
    Lexer lexer = setLexerString(tag);
    check assertToken(lexer, TAG_HANDLE, lexeme = lexeme);
}

function validTagDataGen() returns map<[string, string]> {
    return {
        "primary": ["! ", "!"],
        "secondary": ["!! ", "!!"],
        "named": ["!named! ", "!named!"]
    };
}