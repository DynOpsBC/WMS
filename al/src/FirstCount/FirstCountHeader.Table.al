table 72034 "DOPSWHS First Count Header"
{
    // Kitoko (22 Eki 2026): İlk Sayım — rafsız/alansız madde sayımı. Terminal madde
    // QR'ı okutup adet girer; işlenince okutulan maddelerin lokasyon stoğu sayılan
    // adede eşitlenir. Okutulmayan maddelere dokunulmaz.
    Caption = 'First Count';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS First Counts";
    DrillDownPageId = "DOPSWHS First Counts";

    fields
    {
        field(1; "No."; Code[20]) { Caption = 'No.'; }
        field(2; "Location Code"; Code[10])
        {
            Caption = 'Location Code';
            TableRelation = Location;
        }
        field(3; Status; Option)
        {
            Caption = 'Status';
            OptionMembers = Open,Posted;
            OptionCaption = 'Open,Posted';
        }
        field(4; "Created By"; Code[50]) { Caption = 'Created By'; }
        field(5; "Created DateTime"; DateTime) { Caption = 'Created DateTime'; }
        field(6; "Posted DateTime"; DateTime) { Caption = 'Posted DateTime'; }
        field(7; "Posted By"; Code[50]) { Caption = 'Posted By'; }
        field(8; "Line Count"; Integer)
        {
            Caption = 'Line Count';
            FieldClass = FlowField;
            CalcFormula = count("DOPSWHS First Count Line" where("Count No." = field("No.")));
            Editable = false;
        }
    }

    keys
    {
        key(PK; "No.") { Clustered = true; }
        key(Created; "Created DateTime") { }
    }

    trigger OnInsert()
    var
        FirstCountMgmt: Codeunit "DOPSWHS First Count Mgmt";
    begin
        if "No." = '' then
            "No." := FirstCountMgmt.NextCountNo();
        FirstCountMgmt.CheckLocation("Location Code");
        Status := Status::Open;
        "Created DateTime" := CurrentDateTime();
        if "Created By" = '' then
            "Created By" := CopyStr(UserId(), 1, MaxStrLen("Created By"));
    end;

    trigger OnDelete()
    var
        FirstCountLine: Record "DOPSWHS First Count Line";
    begin
        if Status = Status::Posted then
            Error('İşlenmiş İlk Sayım %1 silinemez.', "No.");
        FirstCountLine.SetRange("Count No.", "No.");
        FirstCountLine.DeleteAll();
    end;
}
