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
