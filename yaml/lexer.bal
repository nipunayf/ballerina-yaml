import ballerina/regex;

enum RegexPattern {
    PRINTABLE_PATTERN = "\\x09\\x0a\\x0d\\x20-\\x7e\\x85\\xa0-\\xd7ff\\xe000-\\xfffd",
    JSON_PATTERN = "\\x09\\x20-\\xffff",
    BOM_PATTERN = "\\xfeff",
    DECIMAL_DIGIT_PATTERN = "0-9",
    HEXADECIMAL_DIGIT_PATTERN = "0-9a-fA-F",
    OCTAL_DIGIT_PATTERN = "0-7",
    BINARY_DIGIT_PATTERN = "0-1",
    LINE_BREAK_PATTERN = "\\x0a\\x0d",
    WORD_PATTERN = "a-zA-Z0-9\\-",
    FLOW_INDICATOR_PATTERN = "\\,\\[\\]\\{\\}",
    WHITESPACE_PATTERN = "\\s\\t",
    URI_CHAR_PATTERN = "#;/\\?:@&=\\+\\$,_\\.!~\\*'\\(\\)\\[\\]"
}

# Represents the state of the Lexer.
enum State {
    LEXER_START,
    LEXER_TAG_PREFIX
}

# Generates tokens based on the YAML lexemes  
class Lexer {
    # Properties to represent current position 
    int index = 0;
    int lineNumber = 0;

    # Line to be lexically analyzed
    string line = "";

    # Value of the generateed token
    string lexeme = "";

    # Current state of the Lexer
    State state = LEXER_START;

    # Incremented when the lexer needs to be aware of the char count.
    private int charCounter = 0;

    # Generates a Token for the next immediate lexeme.
    #
    # + return - If success, returns a token, else returns a Lexical Error 
    function getToken() returns Token|LexicalError {

        // Generate EOL token at the last index
        if (self.index >= self.line.length()) {
            return {token: EOL};
        }

        // Ignore comments from processing
        if (self.line[self.index] == "#") {
            return self.generateToken(EOL);
        }

        match self.state {
            LEXER_START => {
                return check self.stateStart();
            }
            LEXER_TAG_PREFIX => {
                return check self.stateTagPrefix();
            }
            _ => {
                return self.generateError("Invalid state", self.index);
            }
        }

    }

    private function stateTagPrefix() returns Token|LexicalError {

        // Match the global prefix with tag pattern or local tag prefix
        if (self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN], exclusionPatterns = ["!", FLOW_INDICATOR_PATTERN])
        || self.line[self.index] == "!") {
            self.lexeme += self.line[self.index];
            self.index += 1;
            return self.iterate(self.uriCharacter, TAG_PREFIX);
        }

        // Match the global prefix with hexa-decimal value
        if (self.line[self.index] == "%") {
            self.lexeme += "%";

            // Match the first digit of the tag char
            if (self.peek(1) != () && self.matchRegexPattern(HEXADECIMAL_DIGIT_PATTERN, self.index + 1)) {
                self.lexeme += self.line[self.index + 1];

                // Match the second digit of the tag char
                if (self.peek(2) != () && self.matchRegexPattern(HEXADECIMAL_DIGIT_PATTERN, self.index + 2)) {
                    self.lexeme += self.line[self.index + 2];
                    self.index += 3;

                    // Check for URI characters
                    return self.iterate(self.uriCharacter, TAG_PREFIX);
                }
            }
        }

        return self.generateError(self.formatErrorMessage(self.index, TAG_PREFIX), self.index);
    }

    private function stateStart() returns Token|LexicalError {
        if (self.matchRegexPattern(BOM_PATTERN)) {
            return self.generateToken(BOM);
        }

        if (self.matchRegexPattern(LINE_BREAK_PATTERN)) {
            return self.generateToken(LINE_BREAK);
        }

        if (self.matchRegexPattern(DECIMAL_DIGIT_PATTERN)) {
            return self.iterate(self.digit(DECIMAL_DIGIT_PATTERN), DECIMAL);
        }

        match self.line[self.index] {
            "&" => {
                self.index += 1;
                return self.iterate(self.anchorName, ANCHOR);
            }
            " " => {
                return self.iterate(self.whitespace, SEPARATION_IN_LINE);
            }
            "*" => {
                self.index += 1;
                return self.iterate(self.anchorName, ALIAS);
            }
            "-" => {
                return self.generateToken(SEQUENCE_ENTRY);
            }
            "!" => {
                match self.peek(1) {
                    " "|"\t" => { // Primary tag handle
                        self.lexeme = "!";
                        return self.generateToken(TAG_HANDLE);
                    }
                    "!" => { // Secondary tag handle
                        self.lexeme = "!!";
                        self.index += 1;
                        return self.generateToken(TAG_HANDLE);
                    }
                    () => {
                        return self.generateError("Expected a '" + SEPARATION_IN_LINE + "' after primary tag handle", self.index + 1);
                    }
                    _ => { // Check for named tag handles
                        self.lexeme = "!";
                        self.index += 1;
                        return self.iterate(self.tagHandle, TAG_HANDLE, true);
                    }
                }
            }
            "'" => { //TODO: Single-quoted flow scalar

            }
            "\"" => { //TODO: Double-quoted flow scalar

            }
            "%" => { // Directive line
                match self.peek(1) {
                    "T" => {
                        self.index += 1;
                        return check self.tokensInSequence("TAG", DIRECTIVE);
                    }
                    "Y" => {
                        self.index += 1;
                        return check self.tokensInSequence("YAML", DIRECTIVE);
                    }
                    _ => {
                        return self.generateError(self.formatErrorMessage(self.index + 1, DIRECTIVE), self.index + 1);
                    }
                }
            }
            "|" => { // Literal block scalar
                return self.generateToken(LITERAL);
            }
            ">" => { // Folded block scalar
                return self.generateToken(FOLDED);
            }
            "?" => {
                return self.generateToken(MAPPING_KEY);
            }
            ":" => {
                return self.generateToken(MAPPING_VALUE);
            }
            "," => {
                return self.generateToken(SEPARATOR);
            }
            "[" => {
                return self.generateToken(SEQUENCE_START);
            }
            "]" => {
                return self.generateToken(SEQUENCE_END);
            }
            "{" => {
                return self.generateToken(MAPPING_START);
            }
            "}" => {
                return self.generateToken(MAPPING_END);
            }
            "'" => {

            }
            "." => {
                return self.generateToken(DOT);
            }

        }

        return self.generateError("Invalid character", self.index);
    }

    private function uriCharacter(int i) returns boolean|LexicalError {
        if (self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN], i)) {
            self.lexeme += self.line[i];
            return false;
        }
        if self.line[i] == "%" {
            if (self.charCounter > 1 && self.charCounter < 4) {
                return self.generateError("Must have 2 digits for a hexadecimal in URI", i);
            }
            self.lexeme += "%";
            self.charCounter += 1;
            return false;
        }
        if (self.matchRegexPattern(HEXADECIMAL_DIGIT_PATTERN, i) && self.charCounter > 1 && self.charCounter < 4) {
            self.lexeme += self.line[i];
            self.charCounter += 1;
            return false;
        }
        if self.matchRegexPattern([LINE_BREAK_PATTERN, WHITESPACE_PATTERN], i) {
            return false;
        }
        return self.generateError(self.formatErrorMessage(i, TAG_PREFIX), i);
    }

    private function tagHandle(int i) returns boolean|LexicalError {
        if (self.matchRegexPattern(WORD_PATTERN, i)) {
            self.lexeme += self.line[i];
            return false;
        }
        if self.line[i] == "!" {
            self.lexeme += "!";
            return true;
        }
        return self.generateError(self.formatErrorMessage(i, TAG_HANDLE), i);
    }

    private function anchorName(int i) returns boolean|LexicalError {
        if (self.matchRegexPattern([PRINTABLE_PATTERN], i, [LINE_BREAK_PATTERN, BOM_PATTERN, FLOW_INDICATOR_PATTERN, WHITESPACE_PATTERN])) {
            self.lexeme += self.line[i];
            return false;
        }
        return true;
    }

    private function whitespace(int i) returns boolean {
        if (self.line[i] == " ") {
            return false;
        }
        return true;
    }
    # Check for the lexems to crete an DECIMAL token.
    #
    # + digitPattern - Regex pattern of the number system
    # + return - Generates a function which checks the lexems for the given number system.  
    private function digit(string digitPattern) returns function (int i) returns boolean|LexicalError {
        return function(int i) returns boolean|LexicalError {
            if (self.matchRegexPattern(digitPattern, i)) {
                self.lexeme += self.line[i];
                return false;
            }
            return true;
        };
    }

    # Encapsulate a function to run isolatedly on the remaining characters.
    # Function lookaheads to capture the lexems for a targetted token.
    #
    # + process - Function to be executed on each iteration  
    # + successToken - Token to be returned on successful traverse of the characters  
    # + message - Message to display if the end delimeter is not shown  
    # + include - True when the last char belongs to the token
    # + return - Lexical Error if available
    private function iterate(function (int) returns boolean|LexicalError process,
                            YAMLToken successToken,
                            boolean include = false,
                            string message = "") returns Token|LexicalError {

        // Iterate the given line to check the DFA
        foreach int i in self.index ... self.line.length() - 1 {
            if (check process(i)) {
                self.index = include ? i : i - 1;
                return self.generateToken(successToken);
            }
        }
        self.index = self.line.length() - 1;

        // If the lexer does not expect an end delimiter at EOL, returns the token. Else it an error.
        return message.length() == 0 ? self.generateToken(successToken) : self.generateError(message, self.index);
    }

    # Peeks the character succeeding after k indexes. 
    # Returns the character after k spots.
    #
    # + k - Number of characters to peek
    # + return - Character at the peek if not null  
    private function peek(int k) returns string? {
        return self.index + k < self.line.length() ? self.line[self.index + k] : ();
    }

    # Check if the given character matches the regex pattern.
    #
    # + inclusionPatterns - Included the regex patterns
    # + index - Index of the character. Default = self.index  
    # + exclusionPatterns - Exclude the regex pattenrs
    # + return - True if the pattern mathces
    private function matchRegexPattern(string|string[] inclusionPatterns, int? index = (), string|string[]? exclusionPatterns = ()) returns boolean {
        string inclusionPattern = "[" + self.concatenateStringArray(inclusionPatterns) + "]";
        string exclusionPattern = "";

        if (exclusionPatterns != ()) {
            exclusionPattern = "(?![" + self.concatenateStringArray(exclusionPatterns) + "])";
        }
        return regex:matches(self.line[index == () ? self.index : index], exclusionPattern + inclusionPattern + "{1}");
    }

    # Concatenate one or more strings.
    #
    # + strings - Strings to be concatenated
    # + return - Concatenated string
    function concatenateStringArray(string[]|string strings) returns string {
        if (strings is string) {
            return strings;
        }
        string output = "";
        strings.forEach(function(string line) {
            output += line;
        });
        return output;
    }

    # Check if the tokens adhere to the given string.
    #
    # + chars - Expected string  
    # + successToken - Output token if succeed
    # + return - If success, returns the token. Else, returns the parsing error.  
    private function tokensInSequence(string chars, YAMLToken successToken) returns Token|LexicalError {
        foreach string char in chars {
            if (!self.checkCharacter(char)) {
                return self.generateError(self.formatErrorMessage(self.index, successToken), self.index);
            }
            self.index += 1;
        }
        self.lexeme += chars;
        self.index -= 1;
        return self.generateToken(successToken);
    }

    # Assert the character of the current index
    #
    # + expectedCharacters - Expected characters at the current index  
    # + index - Index of the character. If null, takes the lexer's 
    # + return - True if the assertion is true. Else, an lexical error
    private function checkCharacter(string|string[] expectedCharacters, int? index = ()) returns boolean {
        if (expectedCharacters is string) {
            return expectedCharacters == self.line[index == () ? self.index : index];
        } else if (expectedCharacters.indexOf(self.line[index == () ? self.index : index]) == ()) {
            return false;
        }
        return true;
    }

    # Generate a lexical token.
    #
    # + token - TOML token
    # + return - Generated lexical token  
    private function generateToken(YAMLToken token) returns Token {
        self.index += 1;
        string lexemeBuffer = self.lexeme;
        self.lexeme = "";
        return {
            token: token,
            value: lexemeBuffer
        };
    }

    # Generates a Lexical Error.
    #
    # + message - Error message  
    # + index - Index where the Lexical error occurred
    # + return - Constructed Lexcial Error message
    private function generateError(string message, int index) returns LexicalError {
        string text = "Lexical Error at line "
                        + (self.lineNumber + 1).toString()
                        + " index "
                        + index.toString()
                        + ": "
                        + message
                        + ".";
        return error LexicalError(text);
    }

    # Generate the template error message "Invalid character '${char}' for a '${token}'"
    #
    # + index - Index of the character
    # + tokenName - Expected token name
    # + return - Generated error message
    private function formatErrorMessage(int index, YAMLToken tokenName) returns string {
        return "Invalid character '" + self.line[index] + "' for a '" + tokenName + "'";
    }
}
