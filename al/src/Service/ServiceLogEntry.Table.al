/// <summary>
/// Service log: every text typed for a service order (description, notes, resolution) and the
/// steps of the job, with who and when. Entries keep their own copy of the customer, service
/// item and sales order, so the history survives after the service order is invoiced and deleted.
/// </summary>
table 72103 "DOPSWHS Service Log Entry"
{
    Caption = 'Service Log Entry';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Service Log";
    DrillDownPageId = "DOPSWHS Service Log";

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Entry No.'; AutoIncrement = true; }
        field(2; "Logged At"; DateTime) { Caption = 'Date and Time'; }
        field(3; "User ID"; Code[50]) { Caption = 'User'; DataClassification = EndUserIdentifiableInformation; }
        field(4; "Resource No."; Code[20]) { Caption = 'Technician No.'; TableRelation = Resource; }
        field(5; "Technician Name"; Text[100]) { Caption = 'Technician'; }
        field(10; "Service Order No."; Code[20]) { Caption = 'Service Order No.'; }
        field(11; "Service Item Line No."; Integer) { Caption = 'Service Item Line No.'; }
        field(12; "Service Item No."; Code[20]) { Caption = 'Service Item No.'; TableRelation = "Service Item"; }
        field(13; "Service Item Description"; Text[100]) { Caption = 'Service Item'; }
        field(14; "Customer No."; Code[20]) { Caption = 'Customer No.'; TableRelation = Customer; }
        field(15; "Customer Name"; Text[100]) { Caption = 'Customer'; }
        field(16; "Sales Order No."; Code[20]) { Caption = 'Sales Order No.'; }
        field(20; "Entry Type"; Enum "DOPSWHS Service Log Type") { Caption = 'Type'; }
        field(21; "Entry Text"; Text[2048]) { Caption = 'Text'; }
        field(22; "From Terminal"; Boolean) { Caption = 'From Terminal'; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Order; "Service Order No.", "Entry No.") { }
        key(SalesOrder; "Sales Order No.", "Service Order No.", "Entry No.") { }
    }
}
