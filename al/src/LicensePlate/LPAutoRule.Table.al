/// <summary>
/// Location x document type rule that opens license plates automatically for
/// warehouse receipts and shipments and closes them (SSCC + label) on posting.
/// A rule with a blank location applies to every location without its own rule.
/// Evaluated by codeunit "DOPSWHS LP Auto Rule Mgt.".
/// </summary>
table 72236 "DOPSWHS LP Auto Rule"
{
    Caption = 'LP Auto Rule';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS LP Auto Rules";
    DrillDownPageId = "DOPSWHS LP Auto Rules";

    fields
    {
        field(1; "Location Code"; Code[10])
        {
            Caption = 'Location Code';
            DataClassification = CustomerContent;
            TableRelation = Location;
        }
        field(2; "Document Type"; Enum "DOPSWHS Assigned Doc Type")
        {
            Caption = 'Document Type';
            DataClassification = CustomerContent;

            trigger OnValidate()
            begin
                if not ("Document Type" in ["Document Type"::WhseReceipt, "Document Type"::WhseShipment]) then
                    Error(UnsupportedDocTypeErr);
            end;
        }
        field(10; Enabled; Boolean)
        {
            Caption = 'Enabled';
            DataClassification = CustomerContent;
            InitValue = true;
        }
        field(11; "Create Mode"; Enum "DOPSWHS LP Auto Create Mode")
        {
            Caption = 'Create Mode';
            DataClassification = CustomerContent;
        }
        field(12; "LP Template Code"; Code[20])
        {
            Caption = 'LP Template Code';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Template";
        }
        field(13; "Stop On Post"; Boolean)
        {
            Caption = 'Stop On Post (SSCC)';
            DataClassification = CustomerContent;
            InitValue = true;
        }
        field(14; "Print Label On Post"; Boolean)
        {
            Caption = 'Print Label On Post';
            DataClassification = CustomerContent;
        }
        field(15; "Printer Code"; Code[20])
        {
            Caption = 'Printer Code';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS Printer";
        }
        field(16; "Label Copies"; Integer)
        {
            Caption = 'Label Copies';
            DataClassification = CustomerContent;
            MinValue = 0;
            MaxValue = 10;
        }
        field(17; "Fill From Document On Post"; Boolean)
        {
            // Terminal-confirmed lines already materialise LP content. This
            // covers documents posted from the BC client: the empty auto LP is
            // filled from the posted lines before it is stopped.
            Caption = 'Fill From Document On Post';
            DataClassification = CustomerContent;
            InitValue = true;
        }
        field(18; Description; Text[100])
        {
            Caption = 'Description';
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "Location Code", "Document Type") { Clustered = true; }
    }

    trigger OnInsert()
    begin
        if "Create Mode" <> "Create Mode"::None then
            TestField("LP Template Code");
    end;

    trigger OnModify()
    begin
        if "Create Mode" <> "Create Mode"::None then
            TestField("LP Template Code");
    end;

    var
        UnsupportedDocTypeErr: Label 'LP otomasyon kuralı yalnız Ambar Mal Kabul ve Ambar Sevkiyat belgeleri için tanımlanabilir.';
}
