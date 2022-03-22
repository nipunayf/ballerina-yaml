class Composer {

    Parser parser;

    function init(Parser parser) {
        self.parser = parser;
    }

    public function compose() returns anydata[]|ParsingError|LexicalError|ComposingError {
        anydata[] output = [];
        Event event = check self.parser.parse();

        while !(event is EndEvent && event.endType == STREAM) {
            if event is StartEvent && event.startType == SEQUENCE {
                anydata[] seq = check self.sequence();
                output.push(seq);
            }
            if event is StartEvent && event.startType == MAPPING {
                map<anydata> struct = check self.mapping();
                output.push(struct);
            }
            event = check self.parser.parse();
        }

        return output;
    }

    private function sequence() returns anydata[]|LexicalError|ParsingError|ComposingError {
        anydata[] sequence = [];
        Event event = check self.parser.parse();

        while event is ScalarEvent {
            sequence.push(event.value);
        }

        if event is EndEvent && event.endType == SEQUENCE {
            return sequence;
        }

        return self.generateError("Expected to end the sequence");
    }

    private function mapping() returns map<anydata>|LexicalError|ParsingError|ComposingError {
        map<anydata> structure = {};
        Event event = check self.parser.parse();

        while event is ScalarEvent {
            string? key = event.value;

            event = check self.parser.parse();

            if !(event is ScalarEvent) {
                check self.generateError("Unexpected event for a mapping value");
            }

            string? value = (<ScalarEvent>event).value;
            structure[key is string ? key : "null"] = value;

            event = check self.parser.parse();
        }

        if event is EndEvent && event.endType == MAPPING {
            return structure;
        }

        return self.generateError("Expected to end the mapping");
    }

    private function data() {

    }

    # Generates a Parsing Error Error.
    #
    # + message - Error message
    # + return - Constructed Parsing Error message  
    private function generateError(string message) returns ComposingError {
        string text = "Parsing Error at line "
                        + self.parser.lexer.lineNumber.toString()
                        + " index "
                        + self.parser.lexer.index.toString()
                        + ": "
                        + message
                        + ".";
        return error ComposingError(text);
    }
}
