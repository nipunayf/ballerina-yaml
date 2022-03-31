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
        check writeBlockSequence(state);
    }
}

function writeBlockSequence(EmitterState state) returns EmittingError? {
    Event event = getEvent(state);
    boolean emptySequence = true;

    while true {
        // Write scalar event
        if event is ScalarEvent {
            state.output.push(string `- ${event.value.toString()}`);
        }

        if event is EndEvent {
            match event.endType {
                SEQUENCE|STREAM => {
                    if emptySequence {
                        state.output.push("-");
                    }
                    break;
                }
            }
        }

        event = getEvent(state);
        emptySequence = false;
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
