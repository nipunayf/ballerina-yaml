type Event AliasEvent|StreamStartEvent|DocumentStartEvent|SequenceStartEvent|
    MappingStartEvent|ScalarEvent|EndEvent;

type AliasEvent record {|
    string alias;
|};

type StreamStartEvent record {|
    string encoding;
|};

type DocumentStartEvent record {|
    boolean explicit = false;
    string docVersion;
    map<string> tags;
|};

type NodeEvent record {|
    string? anchor = ();
    string? tag = ();
    string? tagHandle  = ();
    // boolean implicit = true;
    // string style = ;
|};

type SequenceStartEvent record {|
    *NodeEvent;
|};

type MappingStartEvent record {|
    *NodeEvent;
|};

type ScalarEvent record {|
    *NodeEvent;
    string value;
|};

type EndEvent record {|
    EndEventType endType;
|};

enum EndEventType {
    END_STREAM,
    END_DOCUMENT,
    END_SEQUENCE,
    END_MAPPING
}
