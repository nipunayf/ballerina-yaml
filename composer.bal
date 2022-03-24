class Composer {
    Parser parser;
    private Event? buffer = ();

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
            if self.buffer == () {
                event = check self.parser.parse();
            } else {
                event = <Event>self.buffer;
                self.buffer = ();
            }
        }

        return sequence;
    }

    private function composeMapping(Event? eventParam = ()) returns map<anydata>|LexicalError|ParsingError|ComposingError {
        map<anydata> structure = {};
        boolean flowStyle = eventParam == ();

        Event event = eventParam == () ? check self.parser.parse() : eventParam;

        while true {
            if event is EndEvent {
                match event.endType {
                    MAPPING => {
                        if flowStyle {
                            break;
                        }
                        return self.generateError("Expected a mapping start event before end event");
                    }
                    SEQUENCE => {
                        return self.generateError("Expected a mapping end event");
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

            if !(<StartEvent|ScalarEvent>event).isKey {
                return self.generateError("Expected a key for a mapping");
            }
            anydata key = check self.composeNode(event, true);

            event = check self.parser.parse();
            anydata value;
            if (<StartEvent|ScalarEvent>event).isKey {
                if flowStyle {
                    return self.generateError("Cannot have block mapping inside a flow mapping");
                }
                value = check self.composeMapping(event);
            } else {
                value = check self.composeNode(event);
            }

            structure[key.toString()] = value;
            event = check self.parser.parse();

            if event is StartEvent|ScalarEvent && event.entry {
                self.buffer = event;
                break;
            }
        }

        return structure;
    }

    // TODO: Tag resolution for 
    // private function composeScalar() returns anydata|LexicalError|ParsingError|ComposingError {
    //     Event event = check self.parser.parse();

    // }

    private function composeNode(Event event, boolean insideMapping = false) returns anydata|LexicalError|ParsingError|ComposingError {

        // Check for +SEQ
        if event is StartEvent && event.startType == SEQUENCE {
            return check self.composeSequence(event.flowStyle);
        }

        // Check for +MAP
        if event is StartEvent && event.startType == MAPPING {
            return check self.composeMapping();
        }

        if event is ScalarEvent && event.isKey && !insideMapping {
            return check self.composeMapping(event);
        }

        // Check for SCALAR
        if event is ScalarEvent {
            return event.value;
        }
    }

    # Generates a Parsing Error Error.
    #
    # + message - Error message
    # + return - Constructed Parsing Error message  
    private function generateError(string message) returns ComposingError {
        string text = "Composing Error at line "
                        + self.parser.lexer.lineNumber.toString()
                        + " index "
                        + self.parser.lexer.index.toString()
                        + ": "
                        + message
                        + ".";
        return error ComposingError(text);
    }
}
