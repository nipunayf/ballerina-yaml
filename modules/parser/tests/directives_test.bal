import ballerina/test;
import yaml.event;

@test:Config {
    groups: ["directives"]
}
function testAccurateYAMLDirective() returns error? {
    ParserState state = check new (["%YAML 1.3", "---"]);
    _ = check parse(state, docType = ANY_DOCUMENT);

    test:assertEquals(state.yamlVersion, "1.3");
}

@test:Config {
    groups: ["directives"]
}
function testDuplicateYAMLDirectives() returns error? {
    check assertParsingError(["%YAML 1.3", "%YAML 1.1"]);
}

@test:Config {
    dataProvider: invalidDirectiveDataGen,
    groups: ["directives"]
}
function testInvalidYAMLDirectives(string line) returns error? {
    check assertParsingError(line);
}

function invalidDirectiveDataGen() returns map<[string]> {
    return {
        "additional dot": ["%YAML 1.2.1"],
        "no space": ["%YAML1.2"],
        "single digit": ["%YAML 1"]
    };
}


@test:Config {}
function testTagDuplicates() returns error? {
    check assertParsingError(["%TAG !a! firstPrefix ", "%TAG !a! secondPrefix "]);
}

@test:Config {
    dataProvider: tagHandlesDataGen
}
function testTagHandles(string line, string tagHandle, string tagPrefix) returns error? {
    ParserState state = check new ([line, "---"]);
    _ = check parse(state, docType = ANY_DOCUMENT);
    test:assertEquals(state.tagHandles[tagHandle], tagPrefix);
}

function tagHandlesDataGen() returns map<[string, string, string]> {
    return {
        "primary": ["%TAG ! local ", "!", "local"],
        "secondary": ["%TAG !! tag:global ", "!!", "tag:global"],
        "named": ["%TAG !a! tag:named ", "!a!", "tag:named"]
    };
}

@test:Config {}
function testInvalidContentInDirectiveDocument() returns error? {
    check assertParsingError(["%TAG ! local", "anything that is not %"]);
}

@test:Config {}
function testInvalidDirectiveInBareDocument() returns error? {
    ParserState state = check new (["---", "%TAG ! local"]);

    _ = check parse(state, docType = ANY_DOCUMENT);
    error|event:Event err = parse(state);

    test:assertTrue(err is ParsingError);
}