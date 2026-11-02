tableextension 72001 "DOPSWHS Serial Info Quality" extends "Serial No. Information"
{
    // KIT-010: same quality hold marker as on Lot No. Information, for serial
    // numbered items (e.g. assembled luminaires inspected one by one).
    fields
    {
        field(72002; "DOPSWHS Quality Hold"; Boolean)
        {
            Caption = 'Quality Hold';
            DataClassification = CustomerContent;
            Editable = false;
            ToolTip = 'Specifies that the serial number is blocked because a quality order is not passed yet. The block is released automatically when the inspection is passed.';
        }
        field(72003; "DOPSWHS Quality Order No."; Code[20])
        {
            Caption = 'Quality Order No.';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = "DOPSWHS Quality Order";
            ToolTip = 'Specifies the quality order that placed the serial number on quality hold.';
        }
    }
}
