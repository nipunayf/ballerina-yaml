import ballerina/io;

public function main() returns error? {
    string[] lines = check io:fileReadLines(".github/workflows/ci.yml");
    Parser parser = check new Parser(lines);
}
