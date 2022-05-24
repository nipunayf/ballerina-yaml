import yaml.lexer;
import yaml.common;

public class ParserState {
    # Properties for the TOML lines
    string[] lines;
    int numLines;
    int lineIndex = -1;

    # Current token
    lexer:Token currentToken = {token: lexer:DUMMY};

    # Previous YAML token
    lexer:YAMLToken prevToken = lexer:DUMMY;

    # Used to store the token after peeked.
    # Used later when the checkToken method is invoked.
    lexer:Token tokenBuffer = {token: lexer:DUMMY};

    # Lexical analyzer tool for getting the tokens
    lexer:LexerState lexerState = new ();

    boolean explicitKey = false;
    
    map<string> customTagHandles = {};

    # YAML version of the document.
    float? yamlVersion = ();

    boolean directiveDocument = false;

    common:Event[] eventBuffer = [];

    public function init(string[] lines) returns ParsingError? {
        self.lines = lines;
        self.numLines = lines.length();
        check self.initLexer();
    }

    function updateLexerContext(lexer:Context context) {
        self.lexerState.context = context;
    }

    public function getLineNumber() returns int => self.lexerState.lineNumber + 1;

    public function getIndex() returns int => self.lexerState.index;

    # Initialize the lexer with the attributes of a new line.
    #
    # + message - Error message to display when if the initialization fails 
    # + return - An error if it fails to initialize  
    function initLexer(string message = "Unexpected end of stream") returns ParsingError? {
        self.lineIndex += 1;
        if self.lineIndex >= self.numLines {
            return generateGrammarError(self, message);
        }
        self.lexerState.line = self.lines[self.lineIndex];
        self.lexerState.index = 0;
        self.lexerState.lineNumber = self.lineIndex;
        self.lexerState.indentStartIndex = -1;
        self.lexerState.tokensForMappingValue = [];
        self.lexerState.lastEscapedChar = -1;
    }
}
