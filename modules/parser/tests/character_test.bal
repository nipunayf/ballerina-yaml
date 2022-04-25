import ballerina/test;
import yaml.event;

@test:Config {
    dataProvider: lineFoldingDataGen
}
function testProcessLineFolding(string[] arr, string value) returns error? {
    check assertParsingEvent(arr, value);
}

function lineFoldingDataGen() returns map<[string[], string]> {
    return {
        "space": [["\"as", "space\""], "as space"],
        "space-empty": [["\"", "space\""], " space"]
    };
}

@test:Config {
    dataProvider: invalidNodeTagDataGen
}
function testInvalidNodeTagToken(string line, boolean isLexical) returns error? {
    check assertParsingError(line, isLexical);
}

function invalidNodeTagDataGen() returns map<[string, boolean]> {
    return {
        "verbatim primary": ["!<!>", true],
        "verbatim empty": ["!<>", true],
        "tag-shorthand no-suffix": ["!e!", false]
    };
}

@test:Config {
    dataProvider: tagShorthandDataGen
}
function testTagShorthandEvent(string line, string tagHandle, string tag) returns error? {
    check assertParsingEvent(line, tagHandle = tagHandle, tag = tag);
}

function tagShorthandDataGen() returns map<[string, string, string]> {
    return {
        "primary": ["!local value", "!", "local"],
        "secondary": ["!!str value", "!!", "str"],
        "named": ["!e!tag value", "!e!", "tag"],
        "escaped": ["!e!tag%21 value", "!e!", "tag!"],
        "double!": ["!%21 value", "!", "!"]
    };
}

@test:Config {
    dataProvider: invalidTagShorthandDataGen
}
function testInvalidTagShorthandEvent(string line, boolean isLexical) returns error? {
    check assertParsingError(line, isLexical);
}

function invalidTagShorthandDataGen() returns map<[string, boolean]> {
    return {
        "no suffix": ["!e! value", false],
        "terminating !": ["!e!tag! value", true]
    };
}

@test:Config {
    dataProvider: nodeSeparateDataGen
}
function testNodeSeparationEvent(string[] arr, string tagHandle) returns error? {
    check assertParsingEvent(arr, "value", "tag", tagHandle, "anchor");
}

function nodeSeparateDataGen() returns map<[string[], string]> {
    return {
        "single space": [["!tag &anchor value"], "!"],
        "verbatim tag": [["!<tag> &anchor value"], ""],
        "new line": [["!!tag", "&anchor value"], "!!"],
        "with comment": [["!tag #first-comment", "#second-comment", "&anchor value"], "!"],
        "anchor first": [["&anchor !tag value"], "!"]
    };
}

@test:Config {}
function testAliasEvent() returns error? {
    ParserState state = check new (["*anchor"]);
    event:Event event = check parse(state);

    test:assertEquals((<event:AliasEvent>event).alias, "anchor");
}

@test:Config {
    dataProvider: endEventDataGen
}
function testEndEvent(string line, event:Collection endType) returns error? {
    ParserState state = check new ([line]);
    event:Event event = check parse(state);

    test:assertEquals((<event:EndEvent>event).endType, endType);
}

function endEventDataGen() returns map<[string, event:Collection]> {
    return {
        "end-sequence": ["]", event:SEQUENCE],
        "end-mapping": ["}", event:MAPPING],
        "end-document": ["...", event:DOCUMENT],
        "end-stream": ["", event:STREAM]
    };
}

@test:Config {
    dataProvider: startEventDataGen
}
function testStartEvent(string line, event:Collection eventType, string? anchor) returns error? {
    ParserState state = check new ([line]);
    event:Event event = check parse(state);

    test:assertEquals((<event:StartEvent>event).startType, eventType);
    test:assertEquals((<event:StartEvent>event).anchor, anchor);
}

function startEventDataGen() returns map<[string, event:Collection, string?]> {
    return {
        "mapping-start with tag": ["&anchor {", event:MAPPING, "anchor"],
        "mapping-start": ["{", event:MAPPING, ()],
        "sequence-start with tag": ["&anchor [", event:SEQUENCE, "anchor"],
        "sequence-start": ["[", event:SEQUENCE, ()]
    };
}