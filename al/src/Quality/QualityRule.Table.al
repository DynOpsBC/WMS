table 72036 "DOPSWHS Quality Rule"
{
    // KIT-009 / INV-009: scope of mandatory quality inspection. A rule names a
    // posting (purchase receipt, assembly output) and narrows it by location,
    // item category (parent categories included), item and vendor; blank means
    // "all". When several rules match, the most specific one decides the timing.
    // Rules are only evaluated when the matching gate is switched on in
    // Advanced WMS Setup, so an empty or disabled rule set changes nothing.
    Caption = 'Quality Inspection Rule';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Quality Rules";
    DrillDownPageId = "DOPSWHS Quality Rules";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
            Editable = false;
        }
        field(10; "Source Type"; Enum "DOPSWHS Quality Rule Source")
        {
            Caption = 'Source Type';

            trigger OnValidate()
            begin
                if "Source Type" = "Source Type"::"Assembly Output" then begin
                    "Vendor No." := '';
                    Timing := Timing::"Before Posting";
                end;
            end;
        }
        field(20; "Location Code"; Code[10])
        {
            Caption = 'Location Code';
            TableRelation = Location;
        }
        field(30; "Item Category Code"; Code[20])
        {
            Caption = 'Item Category Code';
            TableRelation = "Item Category";
        }
        field(40; "Item No."; Code[20])
        {
            Caption = 'Item No.';
            TableRelation = Item;
        }
        field(50; "Vendor No."; Code[20])
        {
            Caption = 'Vendor No.';
            TableRelation = Vendor;

            trigger OnValidate()
            begin
                if "Vendor No." <> '' then
                    TestField("Source Type", "Source Type"::"Purchase Receipt");
            end;
        }
        field(60; Timing; Enum "DOPSWHS Quality Insp. Timing")
        {
            Caption = 'Inspection Timing';

            trigger OnValidate()
            begin
                if Timing = Timing::"After Posting" then
                    TestField("Source Type", "Source Type"::"Purchase Receipt");
            end;
        }
        field(70; Description; Text[100])
        {
            Caption = 'Description';
        }
        field(80; Enabled; Boolean)
        {
            Caption = 'Enabled';
            InitValue = true;
        }
        field(90; "Create Automatically"; Boolean)
        {
            // Before Posting rules: the quality order is created together with
            // the warehouse receipt line (BC and terminal), so the inspector finds
            // it in the quality list before the goods are received.
            Caption = 'Create Automatically';
            InitValue = true;
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(Scope; "Source Type", Enabled)
        {
        }
    }

    /// <summary>Specificity of a matching rule; the highest score wins.</summary>
    procedure Specificity(): Integer
    var
        Score: Integer;
    begin
        if "Item No." <> '' then
            Score += 8;
        if "Item Category Code" <> '' then
            Score += 4;
        if "Vendor No." <> '' then
            Score += 2;
        if "Location Code" <> '' then
            Score += 1;
        exit(Score);
    end;
}
