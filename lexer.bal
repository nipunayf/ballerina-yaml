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
    URI_CHAR_PATTERN = "#;/\\?:@&=\\+\\$,_\\.!~\\*'\\(\\)\\[\\]",
    INDICATOR_PATTERN = "\\-\\?:\\,\\[\\]\\{\\}#&\\*!\\|\\>\\'\\\"%@\\`"
}

# Represents the state of the Lexer.
enum State {
    LEXER_START,
    LEXER_TAG_HANDLE,
    LEXER_TAG_PREFIX,
    LEXER_DIRECTIVE,
    LEXER_DOCUMENT_OUT,
    LEXER_DOUBLE_QUOTE,
    LEXER_SINGLE_QUOTE
}

# Generates tokens based on the YAML lexemes  
class Lexer {
    # Properties to represent current position 
    int index = 0;
    int lineNumber = 0;

    # Line to be lexically analyzed
    string line = "";

    # Value of the generated token
    string lexeme = "";

    # Current state of the Lexer
    State state = LEXER_START;

    # Indentation of the current line   
    int indent = 0;

    # Incremented when the lexer needs to be aware of the char count.
    private int charCounter = 0;

    private map<string> escapedCharMap = {
        "0": "\u{00}",
        "a": "\u{07}",
        "b": "\u{08}",
        "t": "\t",
        "n": "\n",
        "v": "\u{0b}",
        "f": "\u{0c}",
        "r": "\r",
        "e": "\u{1b}",
        "\"": "\"",
        "/": "/",
        "\\": "\\",
        "N": "\u{85}",
        "_": "\u{a0}",
        "L": "\u{2028}",
        "P": "\u{2029}",
        " ": "\u{20}"
    };

    # Generates a Token for the next immediate lexeme.
    #
    # + return - If success, returns a token, else returns a Lexical Error 
    function getToken() returns Token|LexicalError {

        // Generate EOL token at the last index
        if (self.index >= self.line.length()) {
            return self.index == 0 ? self.generateToken(EMPTY_LINE) : {token: EOL};
        }

        if (self.matchRegexPattern(LINE_BREAK_PATTERN)) {
            return self.generateToken(LINE_BREAK);
        }

        match self.state {
            LEXER_START => {
                return check self.stateStart();
            }
            LEXER_TAG_HANDLE => {
                return check self.stateTagHandle();
            }
            LEXER_TAG_PREFIX => {
                return check self.stateTagPrefix();
            }
            LEXER_DIRECTIVE => {
                return check self.stateYamlDirective();
            }
            LEXER_DOCUMENT_OUT => {
                return check self.stateDocumentOut();
            }
            LEXER_DOUBLE_QUOTE => {
                return check self.stateDoubleQuote();
            }
            LEXER_SINGLE_QUOTE => {
                return check self.stateSingleQuote();
            }
            _ => {
                return self.generateError("Invalid state");
            }
        }

    }

    private function stateDoubleQuote() returns Token|LexicalError {
        // Check for empty lines
        if self.peek() == " " {
            Token token = check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
            if self.peek() == () {
                return self.generateToken(EMPTY_LINE);
            }
            self.lexeme += token.value;
        }

        // Terminating delimiter
        if self.peek() == "\"" {
            return self.generateToken(DOUBLE_QUOTE_DELIMITER);
        }

        // Regular double quoted characters
        if self.matchRegexPattern(JSON_PATTERN, exclusionPatterns = ["\""]) {
            return self.iterate(self.scanDoubleQuoteChar, DOUBLE_QUOTE_CHAR);
        }

        return self.generateError(self.formatErrorMessage("double quotes flow style"));
    }

    private function stateSingleQuote() returns Token|LexicalError {
        // Check for empty lines
        if self.peek() == " " {
            Token token = check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
            if self.peek() == () {
                return self.generateToken(EMPTY_LINE);
            }
            self.lexeme += token.value;
        }

        // Escaped single quote
        if self.peek() == "'" && self.peek(1) == "'" {
            self.lexeme += "'";
            self.forward(2);
        }

        // Terminating delimiter
        if self.peek() == "'" {
            if self.lexeme.length() > 0 {
                self.index -= 1;
                return self.generateToken(SINGLE_QUOTE_CHAR);
            }
            return self.generateToken(SINGLE_QUOTE_DELIMITER);
        }

        // Regular single quoted characters
        if self.matchRegexPattern(JSON_PATTERN, exclusionPatterns = ["'"]) {
            return self.iterate(self.scanSingleQuotedChar, SINGLE_QUOTE_CHAR);
        }

        return self.generateError(self.formatErrorMessage("single quote flow style"));
    }

    private function stateYamlDirective() returns Token|LexicalError {
        // Check for decimal digits
        if (self.matchRegexPattern(DECIMAL_DIGIT_PATTERN)) {
            return self.iterate(self.scanDigit(DECIMAL_DIGIT_PATTERN), DECIMAL);
        }

        // Check for decimal point
        if self.peek() == "." {
            return self.generateToken(DOT);
        }

        return self.generateError(self.formatErrorMessage("version number"));
    }

    private function stateDocumentOut() returns Token|LexicalError {
        match self.peek() {
            " " => {
                // Return empty line if there is only whitespace
                // Else, return separation in line
                boolean isFirstChar = self.index == 0;
                Token token = check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
                return (self.peek() == () && isFirstChar) ? self.generateToken(EMPTY_LINE) : token;
            }
            "#" => { // Ignore comments
                return self.generateToken(EOL);
            }
        }

        if (self.matchRegexPattern(BOM_PATTERN)) {
            return self.generateToken(BOM);
        }

        match self.peek() {
            "-" => {
                // Scan for directive marker
                if self.peek(1) == "-" && self.peek(2) == "-" {
                    self.forward(2);
                    return self.generateToken(DIRECTIVE_MARKER);
                }

                // Scan for planar characters
                self.lexeme += "-";
                self.forward();
                if self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN]) {
                    return self.iterate(self.scanPlanarChar, PLANAR_CHAR);
                }
            }
            "." => {
                return self.tokensInSequence("...", DOCUMENT_MARKER);
            }
            "%" => { // Directive line
                self.forward();
                match self.peek() {
                    "T" => {
                        return check self.tokensInSequence("TAG", DIRECTIVE);
                    }
                    "Y" => {
                        return check self.tokensInSequence("YAML", DIRECTIVE);
                    }
                    _ => {
                        return self.generateError(self.formatErrorMessage(DIRECTIVE));
                    }
                }
            }
            "!" => {

            }
            ":" => {
                self.lexeme += ":";
                self.forward();
                if self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN]) {
                    return self.iterate(self.scanPlanarChar, PLANAR_CHAR);
                }
            }
            "?" => {
                self.lexeme += "?";
                self.forward();
                if self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN]) {
                    return self.iterate(self.scanPlanarChar, PLANAR_CHAR);
                }
            }
            "\"" => { // Process double quote flow style value
                return self.generateToken(DOUBLE_QUOTE_DELIMITER);
            }
            "'" => {
                return self.generateToken(SINGLE_QUOTE_DELIMITER);
            }
        }

        // Check for first character of planar scalar
        if self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN, INDICATOR_PATTERN]) {
            return self.iterate(self.scanPlanarChar, PLANAR_CHAR);
        }
        return self.generateError(self.formatErrorMessage("document prefix"));
    }

    private function stateTagHandle() returns Token|LexicalError {
        // Check fo primary, secondary, and named tag handles
        if self.peek() == "!" {
            match self.peek(1) {
                " "|"\t" => { // Primary tag handle
                    self.lexeme = "!";
                    return self.generateToken(TAG_HANDLE);
                }
                "!" => { // Secondary tag handle
                    self.lexeme = "!!";
                    self.forward();
                    return self.generateToken(TAG_HANDLE);
                }
                () => {
                    return self.generateError(string `Expected a ${SEPARATION_IN_LINE} after primary tag handle`);
                }
                _ => { // Check for named tag handles
                    self.lexeme = "!";
                    self.forward();
                    return self.iterate(self.scanTagHandle, TAG_HANDLE, true);
                }
            }
        }

        // Check for separation-in-space before the tag prefix
        if self.peek() == " " {
            return check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
        }

        return self.generateError("Expected '!' to start the tag handle");
    }

    # Perform scanning for tag prefixes.
    #
    # + return - The respective token on success. Else, an error.
    private function stateTagPrefix() returns Token|LexicalError {

        // Match the global prefix with tag pattern or local tag prefix
        if (self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN], exclusionPatterns = ["!", FLOW_INDICATOR_PATTERN])
        || self.peek() == "!") {
            self.lexeme += <string>self.peek();
            self.forward();
            return self.iterate(self.scanURICharacter, TAG_PREFIX);
        }

        // Match the global prefix with hexadecimal value
        if (self.peek() == "%") {
            self.lexeme += "%";

            // Match the first digit of the tag char
            if (self.peek(1) != () && self.matchRegexPattern(HEXADECIMAL_DIGIT_PATTERN, index = self.index + 1)) {
                self.lexeme += self.line[self.index + 1];

                // Match the second digit of the tag char
                if (self.peek(2) != () && self.matchRegexPattern(HEXADECIMAL_DIGIT_PATTERN, index = self.index + 2)) {
                    self.lexeme += self.line[self.index + 2];
                    self.forward(3);

                    // Check for URI characters
                    return self.iterate(self.scanURICharacter, TAG_PREFIX);
                }
            }
        }

        return self.generateError(self.formatErrorMessage(TAG_PREFIX));
    }

    private function stateStart() returns Token|LexicalError {

        match self.peek() {
            " " => {
                // Return empty line if there is only whitespace
                // Else, return separation in line
                Token token = check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
                return self.peek() == () ? self.generateToken(EMPTY_LINE) : token;
            }
            "#" => { // Ignore comments
                return self.generateToken(EOL);
            }
        }

        if (self.matchRegexPattern(DECIMAL_DIGIT_PATTERN)) {
            return self.iterate(self.scanDigit(DECIMAL_DIGIT_PATTERN), DECIMAL);
        }

        match self.peek() {
            "&" => {
                self.forward();
                return self.iterate(self.scanAnchorName, ANCHOR);
            }
            "*" => {
                self.forward();
                return self.iterate(self.scanAnchorName, ALIAS);
            }
            "-" => {
                return self.generateToken(SEQUENCE_ENTRY);
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
            "." => {
                return self.generateToken(DOT);
            }

        }

        return self.generateError(self.formatErrorMessage("indicator"));
    }

    # Scan lexemes for the escaped characters.
    # Adds the processed escaped character to the lexeme.
    #
    # + return - An error on failure
    private function scanEscapedCharacter() returns LexicalError? {
        string currentChar;

        // Process double escape character
        if (self.peek() == ()) {
            self.lexeme += "\\";
            return;
        } else {
            currentChar = <string>self.peek();
        }

        // Check for predefined escape characters
        if (self.escapedCharMap.hasKey(currentChar)) {
            self.lexeme += <string>self.escapedCharMap[currentChar];
            return;
        }

        // Check for unicode characters
        match currentChar {
            "x" => {
                check self.scanUnicodeEscapedCharacters("x", 2);
                return;
            }
            "u" => {
                check self.scanUnicodeEscapedCharacters("u", 4);
                return;
            }
            "U" => {
                check self.scanUnicodeEscapedCharacters("U", 8);
                return;
            }
        }
        return self.generateError(self.formatErrorMessage("escaped character"));
    }

    # Process the hex codes under the unicode escaped character.
    #
    # + escapedChar - Escaped character before the digits  
    # + length - Number of digits
    # + return - An error on failure
    private function scanUnicodeEscapedCharacters(string escapedChar, int length) returns LexicalError? {

        // Check if the required digits do not overflow the current line.
        if self.line.length() <= length + self.index {
            return self.generateError("Expected " + length.toString() + " characters for the '\\" + escapedChar + "' unicode escape");
        }

        string unicodeDigits = "";

        // Check if the digits adhere to the hexadecimal code pattern.
        foreach int i in 0 ... length - 1 {
            self.forward();
            if self.matchRegexPattern(HEXADECIMAL_DIGIT_PATTERN) {
                unicodeDigits += <string>self.peek();
                continue;
            }
            return self.generateError(self.formatErrorMessage("unicode hex escape"));
        }

        // Check if the lexeme can be converted to hexadecimal
        int|error hexResult = 'int:fromHexString(unicodeDigits);
        if hexResult is error {
            return self.generateError('error:message(hexResult));
        }

        // Check if there exists a unicode string for the hexadecimal value
        string|error unicodeResult = 'string:fromCodePointInt(hexResult);
        if unicodeResult is error {
            return self.generateError('error:message(unicodeResult));
        }

        self.lexeme += unicodeResult;
    }

    # Process double quoted scalar values.
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanDoubleQuoteChar() returns boolean|LexicalError {
        // Process nb-json characters
        if self.matchRegexPattern(JSON_PATTERN, exclusionPatterns = ["\\\\", "\""]) {
            self.lexeme += <string>self.peek();
            return false;
        }

        // Process escaped characters
        if (self.peek() == "\\") {
            self.forward();
            check self.scanEscapedCharacter();
            return false;
        }

        // Terminate when delimiter is found
        if self.peek() == "\"" {
            return true;
        }

        return self.generateError(self.formatErrorMessage(DOUBLE_QUOTE_CHAR));
    }

    # Process double quoted scalar values.
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanSingleQuotedChar() returns boolean|LexicalError {
        // Process nb-json characters
        if self.matchRegexPattern(JSON_PATTERN, exclusionPatterns = ["'"]) {
            self.lexeme += <string>self.peek();
            return false;
        }

        // Terminate when the delimiter is found
        if self.peek() == "'" {
            if self.peek(1) == "'" {
                self.lexeme += "'";
                self.forward();
                return false;
            }
            return true;
        }

        return self.generateError(self.formatErrorMessage(SINGLE_QUOTE_CHAR));
    }

    private function scanPlanarChar() returns boolean|LexicalError {
        // Store the whitespace before a ns-planar char
        string whitespace = "";
        int numWhitespace = 0;
        while self.peek() == "\t" || self.peek() == " " {
            whitespace += <string>self.peek();
            numWhitespace += 1;
            self.forward();
        }

        // Check if EOL is reached
        if self.peek() == () {
            self.forward(-numWhitespace);
            return true;
        }

        // Process ns-plain-safe character
        //TODO: exclude flow indicator where necessary
        if self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN, "#", ":"]) {
            self.lexeme += whitespace + <string>self.peek();
            return false;
        }

        // Check for comments with a space before it
        if self.peek() == "#" {
            if self.peek(-1) == " " {
                return true;
            }
            self.lexeme += whitespace + "#";
            return false;
        }

        // Check for mapping value with a space after it 
        if self.peek() == ":" {
            if self.peek() == " " {
                return true;
            }
            self.lexeme += whitespace + ":";
            return false;
        }

        // If the whitespace is at the trail, discard it from the planar chars
        if numWhitespace > 0 {
            self.forward(-numWhitespace);
            return true;
        }

        //TODO: consider the actions for incorrect planar char
        return self.generateError(self.formatErrorMessage(PLANAR_CHAR));
    }

    # Scan the lexeme for URI characters
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanURICharacter() returns boolean|LexicalError {

        // Check for URI characters
        if (self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN])) {
            self.lexeme += <string>self.peek();
            return false;
        }

        // Check for hexadecimal values
        if self.peek() == "%" {
            if (self.charCounter > 1 && self.charCounter < 4) {
                return self.generateError("Must have 2 digits for a hexadecimal in URI");
            }
            self.lexeme += "%";
            self.charCounter += 1;
            return false;
        }

        //  
        if (self.matchRegexPattern(HEXADECIMAL_DIGIT_PATTERN) && self.charCounter > 1 && self.charCounter < 4) {
            self.lexeme += <string>self.peek();
            self.charCounter += 1;
            return false;
        }

        // Ignore the comments
        if self.matchRegexPattern([LINE_BREAK_PATTERN, WHITESPACE_PATTERN]) {
            return false;
        }

        return self.generateError(self.formatErrorMessage(TAG_PREFIX));
    }

    # Description
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanTagHandle() returns boolean|LexicalError {

        // Scan the word of the name tag.
        if (self.matchRegexPattern(WORD_PATTERN)) {
            self.lexeme += <string>self.peek();
            return false;
        }

        // Scan the end delimiter of the tag.
        if self.peek() == "!" {
            self.lexeme += "!";
            return true;
        }
        return self.generateError(self.formatErrorMessage(TAG_HANDLE));
    }

    # Scan the lexeme for the anchor name.
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanAnchorName() returns boolean|LexicalError {
        if (self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, FLOW_INDICATOR_PATTERN, WHITESPACE_PATTERN])) {
            self.lexeme += <string>self.peek();
            return false;
        }
        return true;
    }

    # Scan the white spaces for a line-in-separation.
    #
    # + return - False to continue. True to terminate the token.
    private function scanWhitespace() returns boolean {
        if self.peek() == " " {
            self.lexeme += " ";
            return false;
        }
        return true;
    }
    # Check for the lexemes to crete an DECIMAL token.
    #
    # + digitPattern - Regex pattern of the number system
    # + return - Generates a function which checks the lexemes for the given number system.  
    private function scanDigit(string digitPattern) returns function () returns boolean|LexicalError {
        return function() returns boolean|LexicalError {
            if (self.matchRegexPattern(digitPattern)) {
                self.lexeme += <string>self.peek();
                return false;
            }
            return true;
        };
    }

    # Encapsulate a function to run isolated on the remaining characters.
    # Function lookahead to capture the lexemes for a targeted token.
    #
    # + process - Function to be executed on each iteration  
    # + successToken - Token to be returned on successful traverse of the characters  
    # + message - Message to display if the end delimiter is not shown  
    # + include - True when the last char belongs to the token
    # + return - Lexical Error if available
    private function iterate(function () returns boolean|LexicalError process,
                            YAMLToken successToken,
                            boolean include = false,
                            string message = "") returns Token|LexicalError {

        // Iterate the given line to check the DFA
        while self.index < self.line.length() {
            if (check process()) {
                self.index = include ? self.index : self.index - 1;
                return self.generateToken(successToken);
            }
            self.forward();
        }
        self.index = self.line.length() - 1;

        // If the lexer does not expect an end delimiter at EOL, returns the token. Else it an error.
        return message.length() == 0 ? self.generateToken(successToken) : self.generateError(message);
    }

    # Peeks the character succeeding after k indexes. 
    # Returns the character after k spots.
    #
    # + k - Number of characters to peek. Default = 0
    # + return - Character at the peek if not null  
    private function peek(int k = 0) returns string? {
        return self.index + k < self.line.length() ? self.line[self.index + k] : ();
    }

    # Increment the index of the column by k indexes
    #
    # + k - Number of indexes to forward. Default = 1
    private function forward(int k = 1) {
        if (self.index + k <= self.line.length()) {
            self.index += k;
        }
    }

    # Check if the given character matches the regex pattern.
    #
    # + inclusionPatterns - Included the regex patterns
    # + index - Index of the character. Default = self.index  
    # + exclusionPatterns - Exclude the regex patterns
    # + return - True if the pattern matches
    private function matchRegexPattern(string|string[] inclusionPatterns, string|string[]? exclusionPatterns = (), int? index = ()) returns boolean {
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
            // The expected character is not found
            if (self.peek() == () || !self.checkCharacter(char)) {
                return self.generateError(string `Expected '${char}' for ${successToken}`);
            }
            self.forward();
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
        self.forward();
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
    # + return - Constructed Lexical Error message
    private function generateError(string message) returns LexicalError {
        string text = "Lexical Error at line "
                        + (self.lineNumber + 1).toString()
                        + " index "
                        + self.index.toString()
                        + ": "
                        + message
                        + ".";
        return error LexicalError(text);
    }

    # Generate the template error message "Invalid character '${char}' for a '${token}'"
    #
    # + value - Expected token name or the value
    # + return - Generated error message
    private function formatErrorMessage(YAMLToken|string value) returns string {
        return "Invalid character '" + <string>self.peek() + "' for a '" + <string>value + "'";
    }
}
