tableextension 72000 "DOPSWHS Lot No. Info Quality" extends "Lot No. Information"
{
    // KIT-010: marks a lot that was blocked by a quality order. Only lots the
    // quality hold blocked itself are released again; a lot blocked by hand
    // keeps its block when its inspection passes.
    fields
    {
        field(72000; "DOPSWHS Quality Hold"; Boolean)
        {
            Caption = 'Quality Hold';
            DataClassification = CustomerContent;
            Editable = false;
            ToolTip = 'Specifies that the lot is blocked because a quality order is not passed yet. The block is released automatically when the inspection is passed.';
        }
        field(72001; "DOPSWHS Quality Order No."; Code[20])
        {
            Caption = 'Quality Order No.';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = "DOPSWHS Quality Order";
            ToolTip = 'Specifies the quality order that placed the lot on quality hold.';
        }
    }
}
