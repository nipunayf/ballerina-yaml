# Represents an error caused by parser
type ParsingError distinct error;

# Parses the TOML document using the lexer
class Parser {
    # Properties for the TOML lines
    private string[] lines;
    private int numLines;
    private int lineIndex = -1;

    # Current token
    private Token currentToken = {token: DUMMY};

    # Hold the lexemes until the final value is generated
    private string lexemeBuffer = "";

    # Lexical analyzer tool for getting the tokens
    private Lexer lexer = new Lexer();

    function init(string[] lines) {
        self.lines = lines;
        self.numLines = lines.length();
    }

    # Assert the next lexer token with the predicted token.
    # If no token is provided, then the next token is retrieved without an error checking.
    # Hence, the error checking must be done explicitly.
    #
    # + expectedTokens - Predicted token or tokens
    # + customMessage - Error message to be displayed if the expected token not found  
    # + return - Parsing error if not found
    private function checkToken(YAMLToken|YAMLToken[] expectedTokens = DUMMY, string customMessage = "") returns error? {
        YAMLToken prevToken = self.currentToken.token;
        self.currentToken = check self.lexer.getToken();

        // Bypass error handling.
        if (expectedTokens == DUMMY) {
            return;
        }

        // Automatically generates a template error message if there is no custom message.
        string errorMessage = customMessage.length() == 0
                                ? check self.formatErrorMessage(1, expectedTokens, prevToken)
                                : customMessage;

        // Generate an error if the expected token differ from the actual token.
        if (expectedTokens is YAMLToken) {
            if (self.currentToken.token != expectedTokens) {
                return self.generateError(errorMessage);
            }
        } else {
            if (expectedTokens.indexOf(self.currentToken.token) == ()) {
                return self.generateError(errorMessage);
            }
        }
    }

    # Initialize the lexer with the attributes of a new line.
    #
    # + message - Error messgae to display when if the initalization fails 
    # + incrementLine - Sets the next line to the lexer
    # + return - An error if it fails to initialize  
    private function initLexer(string message, boolean incrementLine = true) returns error? {
        if (incrementLine) {
            self.lineIndex += 1;
        }
        if (self.lineIndex >= self.numLines) {
            return self.generateError(message);
        }
        self.lexer.line = self.lines[self.lineIndex];
        self.lexer.index = 0;
        self.lexer.lineNumber = self.lineIndex;
    }

    # Generates a Parsing Error Error.
    #
    # + message - Error message
    # + return - Constructed Parsing Error message  
    private function generateError(string message) returns ParsingError {
        string text = "Parsing Error at line "
                        + self.lexer.lineNumber.toString()
                        + " index "
                        + self.lexer.index.toString()
                        + ": "
                        + message
                        + ".";
        return error ParsingError(text);
    }

    # Generate a standard error message based on the type.
    #
    # 1 - Expected ${expectedTokens} after ${beforeToken}, but found ${actualToken}
    #
    # 2 - Duplicate key exists for ${value}
    #
    # + messageType - Number of the template message
    # + expectedTokens - Predicted tokens  
    # + beforeToken - Toekn before the predicetd token  
    # + value - Any value name. Commonly used to indicate keys.
    # + return - If success, the generated error message. Else, an error message.
    private function formatErrorMessage(
            int messageType,
            YAMLToken|YAMLToken[] expectedTokens = DUMMY,
            YAMLToken beforeToken = DUMMY,
            string value = "") returns string|error {

        match messageType {
            1 => { // Expected ${expectedTokens} after ${beforeToken}, but found ${actualToken}
                if (expectedTokens == DUMMY || beforeToken == DUMMY) {
                    return error("Token parameters cannot be null for this template error message.");
                }
                string expectedTokensMessage;
                if (expectedTokens is YAMLToken[]) { // If multiplke tokens
                    string tempMessage = expectedTokens.reduce(function(string message, YAMLToken token) returns string {
                        return message + " '" + token + "' or";
                    }, "");
                    expectedTokensMessage = tempMessage.substring(0, tempMessage.length() - 3);
                } else { // If a singel token
                    expectedTokensMessage = " '" + expectedTokens + "'";
                }
                return "Expected" + expectedTokensMessage + " after '" + beforeToken + "', but found '" + self.currentToken.token + "'";
            }

            2 => { // Duplicate key exists for ${value}
                if (value.length() == 0) {
                    return error("Value cannot be empty for this template message");
                }
                return "Duplicate key exists for '" + value + "'";
            }

            _ => {
                return error("Invalid message type number. Enter a value between 1-2");
            }
        }
    }
}
