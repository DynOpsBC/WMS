table 50107 "WMS Data Inquiry"
{
    Caption = 'WMS Data Inquiry';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Inquiry Code"; Code[20]) { Caption = 'Inquiry Code'; NotBlank = true; }
        field(2; Description; Text[100]) { Caption = 'Description'; }
        field(3; "Source Table No."; Integer) { Caption = 'Source Table No.'; }
        field(4; "Filter Expression"; Text[250]) { Caption = 'Filter Expression'; }
        field(5; "Mobile Page Layout"; Text[2048]) { Caption = 'Mobile Page Layout'; }
    }
    keys { key(PK; "Inquiry Code") { Clustered = true; } }
}
