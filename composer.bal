class Composer {
    Parser parser;
    private Event? buffer = ();
    private map<anydata> anchorBuffer = {};

    function init(Parser parser) {
        self.parser = parser;
    }

    public function compose() returns anydata[]|ParsingError|LexicalError|ComposingError {
        anydata[] output = [];
        Event event = check self.parser.parse();

        while !(event is EndEvent && event.endType == STREAM) {
            output.push(check self.composeNode(event));
            event = check self.parser.parse();
        }

        return output;
    }

    private function composeSequence(boolean flowStyle) returns anydata[]|LexicalError|ParsingError|ComposingError {
        anydata[] sequence = [];
        Event event = check self.parser.parse();

        while true {
            if event is EndEvent {
                match event.endType {
                    MAPPING => {
                        return self.generateError("Expected a sequence end event");
                    }
                    SEQUENCE => {
                        break;
                    }
                    DOCUMENT|STREAM => {
                        if !flowStyle {
                            break;
                        }
                        return self.generateError("Expected a sequence end event");
                    }
                }
            }

            if event is DocumentStartEvent {
                if !flowStyle {
                    break;
                }
                return self.generateError("Expected a sequence end event");
            }

            sequence.push(check self.composeNode(event));
            event = check self.parser.parse();
        }

        return sequence;
    }

    private function composeMapping(boolean flowStyle) returns map<anydata>|LexicalError|ParsingError|ComposingError {
        map<anydata> structure = {};
        Event event = check self.parser.parse(EXPECT_KEY);

        while true {
            if event is EndEvent {
                match event.endType {
                    MAPPING => {
                        break;
                    }
                    SEQUENCE => {
                        return self.generateError("Expected a mapping end event");
                    }
                    DOCUMENT|STREAM => {
                        if !flowStyle {
                            break;
                        }
                        return self.generateError("Expected a mapping end event");
                    }
                }
            }

            if event is DocumentStartEvent {
                if !flowStyle {
                    break;
                }
                return self.generateError("Expected a sequence end event");
            }

            if !(event is StartEvent|ScalarEvent) {
                return self.generateError("Expected a key for a mapping");
            }

            anydata key = check self.composeNode(event);
            event = check self.parser.parse(EXPECT_VALUE);
            anydata value = check self.composeNode(event);

            structure[key.toString()] = value;
            event = check self.parser.parse(EXPECT_KEY);
        }

        return structure;
    }

    // TODO: Tag resolution for 
    // private function composeScalar() returns anydata|LexicalError|ParsingError|ComposingError {
    //     Event event = check self.parser.parse();

    // }

    private function composeNode(Event event) returns anydata|LexicalError|ParsingError|ComposingError {
        anydata output;

        // Check for +SEQ
        if event is StartEvent && event.startType == SEQUENCE {
            output = check self.composeSequence(event.flowStyle);
            check self.checkAnchor(event, output);
            return output;
        }

        // Check for +MAP
        if event is StartEvent && event.startType == MAPPING {
            output = check self.composeMapping(event.flowStyle);
            check self.checkAnchor(event, output);
            return output;
        }

        // Check for aliases
        if event is AliasEvent {
            return self.anchorBuffer.hasKey(event.alias)
                ? self.anchorBuffer[event.alias]
                : self.generateError(string `The anchor '${event.alias}' does not exist`);
        }

        // Check for SCALAR
        if event is ScalarEvent {
            output = event.value;
            check self.checkAnchor(event, output);
            return output;
        }
    }

    private function checkAnchor(StartEvent|ScalarEvent event, anydata assignedValue) returns ComposingError? {
        if event.anchor != () {
            if self.anchorBuffer.hasKey(<string>event.anchor) {
                return self.generateError(string `Duplicate anchor definition of '${<string>event.anchor}'`);
            }
            self.anchorBuffer[<string>event.anchor] = assignedValue;
        }
    }

    # Generates a Parsing Error Error.
    #
    # + message - Error message
    # + return - Constructed Parsing Error message  
    private function generateError(string message) returns ComposingError {
        string text = "Composing Error at line "
                        + (self.parser.lexer.lineNumber + 1).toString()
                        + " index "
                        + self.parser.lexer.index.toString()
                        + ": "
                        + message
                        + ".";
        return error ComposingError(text);
    }
}
