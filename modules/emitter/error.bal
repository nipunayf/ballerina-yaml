# Represents an error caused by emitter
type EmittingError distinct error;

# Generates a Emitting Error.
#
# + message - message string
# + return - Constructed Emitting Error message  
function generateError(string message) returns EmittingError {
    return error EmittingError(string `Emitting Error: ${message}.`);
}
