// "Sales order this service is for": typed in the office or picked on the terminal. The same
// field number on the posted documents lets standard posting carry the value over.
tableextension 72121 "DOPSWHS Svc Header Sales Order" extends "Service Header"
{
    fields
    {
        field(72101; "DOPSWHS Sales Order No."; Code[20])
        {
            Caption = 'Sales Order No.';
            DataClassification = CustomerContent;
            TableRelation = "Sales Header"."No." where("Document Type" = const(Order));
            // The sales order may already be invoiced and gone; its number must still be accepted.
            ValidateTableRelation = false;

            trigger OnValidate()
            var
                ServiceLog: Codeunit "DOPSWHS Service Log";
            begin
                if "Document Type" = "Document Type"::Order then
                    ServiceLog.SetSalesOrder("No.", "DOPSWHS Sales Order No.");
            end;
        }
    }
}

tableextension 72122 "DOPSWHS Svc Shpt. Sales Order" extends "Service Shipment Header"
{
    fields
    {
        field(72101; "DOPSWHS Sales Order No."; Code[20])
        {
            Caption = 'Sales Order No.';
            DataClassification = CustomerContent;
        }
    }
}

tableextension 72123 "DOPSWHS Svc Inv. Sales Order" extends "Service Invoice Header"
{
    fields
    {
        field(72101; "DOPSWHS Sales Order No."; Code[20])
        {
            Caption = 'Sales Order No.';
            DataClassification = CustomerContent;
        }
    }
}
