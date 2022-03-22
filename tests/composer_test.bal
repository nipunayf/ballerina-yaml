import ballerina/test;

@test:Config {
    dataProvider: nativeDataStructureDataGen
}
function testGenerateNativeDataStructure(string|string[] line, anydata structure) returns error? {
    Parser parser = check new Parser((line is string) ? [line] : line);
    Composer composer = new Composer(parser);
    anydata[] output = check composer.compose();

    test:assertEquals(output[0], structure);
}

function nativeDataStructureDataGen() returns map<[string|string[], anydata]> {
    return {
        "empty sequence": ["[]", []],
        "mapping": ["{key: value}", {"key": "value"}]
    };
}