pageextension 72315 "DOPSWHS Whse Pick Line LP" extends "Whse. Pick Subform"
{
    layout
    {
        addafter("Bin Code")
        {
            field("DOPSWHS Source LP No."; Rec."LP No.")
            {
                ApplicationArea = All;
                Caption = 'Source LP No.';
                Editable = IsProductionTake;
                ToolTip = 'Select the LP on a production Take line. Registering the pick reduces that LP by the quantity taken from its source bin.';
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        IsProductionTake :=
            (Rec."Action Type" = Rec."Action Type"::Take) and
            (Rec."Source Type" = Database::"Prod. Order Component");
    end;

    var
        IsProductionTake: Boolean;
}
