type EmitterState record {|
    string[] output;
    string indent;
    Event[] events;
|};

function emit(Event[] events, int indentationPolicy = 2) returns string[]|EmittingError {
    string indent = "";
    foreach int i in 1 ... indentationPolicy {
        indent += " ";
    }

    EmitterState state = {
        output: [],
        indent,
        events
    };

    while state.events.length() != 0 {
        check write(state);
    }

    return state.output;
}

function write(EmitterState state) returns EmittingError? {
    Event event = getEvent(state);

    // Write block sequence
    if event is StartEvent && event.startType == SEQUENCE {
        if event.flowStyle {
            state.output.push(check writeFlowSequence(state));
        } else {
            check writeBlockSequence(state, "");
        }
        return;
    }

    if event is StartEvent && event.startType == MAPPING {
        check writeBlockMapping(state, "");
        return;
    }

    if event is ScalarEvent {
        state.output.push(event.value == () ? "" : <string>event.value);
        return;
    }
}

function writeFlowSequence(EmitterState state) returns string|EmittingError {
    string line = "[";
    Event event = getEvent(state);

    while true {
        if event is EndEvent {
            match event.endType {
                SEQUENCE|STREAM => {
                    break;
                }
            }
        }

        if event is ScalarEvent {
            line += event.value.toString();
        }

        if event is StartEvent {
            match event.startType {
                SEQUENCE => {
                    line += check writeFlowSequence(state);
                }
            }
        }

        line += ", ";
        event = getEvent(state);
    }
    
    // Trim the trailing separator
    line = line.length() > 2 ? line.substring(0, line.length() - 2) : line;
    line += "]";
    return line;
}

function writeBlockSequence(EmitterState state, string whitespace) returns EmittingError? {
    Event event = getEvent(state);
    boolean emptySequence = true;

    while true {
        // Write scalar event
        if event is ScalarEvent {
            state.output.push(string `${whitespace}- ${event.value.toString()}`);
        }

        if event is EndEvent {
            match event.endType {
                SEQUENCE|STREAM => {
                    if emptySequence {
                        state.output.push(whitespace + "-");
                    }
                    break;
                }
            }
        }

        if event is StartEvent {
            match event.startType {
                SEQUENCE => {
                    if event.flowStyle {
                        state.output.push(whitespace + "- " + check writeFlowSequence(state));
                    } else {
                        state.output.push(whitespace + "-");
                        check writeBlockSequence(state, whitespace);
                    }
                }
                MAPPING => {
                    if event.flowStyle {

                    } else {
                        check writeBlockMapping(state, whitespace + state.indent);
                    }
                }
            }
        }

        event = getEvent(state);
        emptySequence = false;
    }
}

function writeBlockMapping(EmitterState state, string whitespace) returns EmittingError? {
    Event event = getEvent(state);
    string line;

    while true {
        line = "";
        if event is EndEvent {
            match event.endType {
                MAPPING|STREAM => {
                    break;
                }
            }
        }

        if event is ScalarEvent {
            if event.isKey {
                line += whitespace + event.value.toString() + ": ";
            } else {
                return generateError("Expected a key before a value in mapping");
            }
        }

        event = getEvent(state);

        if event is ScalarEvent {
            if event.isKey {
                return generateError("Expected a value after key");
            }
            line += event.value.toString();
            state.output.push(line);
        }

        if event is StartEvent {
            state.output.push(line);
            match event.startType {
                MAPPING => {
                    check writeBlockMapping(state, whitespace + state.indent);
                }
                SEQUENCE => {
                    check writeBlockSequence(state, whitespace);
                }
            }
        }

        line = "";
        event = getEvent(state);
    }
}

function getEvent(EmitterState state) returns Event {
    if state.events.length() < 1 {
        return {endType: STREAM};
    }
    return state.events.remove(0);
}

# Generates a Emitting Error.
#
# + message - Error message
# + return - Constructed Parsing Error message  
function generateError(string message) returns EmittingError {
    return error EmittingError(string `Emitting Error: ${message}.`);
}
