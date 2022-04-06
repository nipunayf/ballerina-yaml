import ballerina/io;

public function main() returns error? {
    // string[] lines = check io:fileReadLines(".github/workflows/ci.yml");
    // Parser parser = check new (lines);

    // Composer composer = new (parser);
    // anydata[] result = check composer.compose();
    // map<anydata> resultMap = check result[0].ensureType();

    json input = check io:fileReadJson("ci.json");
    map<anydata> resultMap = check input.ensureType();

    resultMap["name"] = "Modified CI build";

    Serializer serializer = new (4);
    Event[] events = check serializer.serialize(resultMap, 0);

    string[] outputLines = check emit(events, 4);
    check io:fileWriteLines("ci.yaml", outputLines);
}
