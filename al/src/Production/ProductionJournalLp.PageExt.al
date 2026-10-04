pageextension 72319 "DOPSWHS Production Jnl LP" extends "Production Journal"
{
    layout
    {
        addafter("Bin Code")
        {
            field("DOPSWHS LP No."; Rec."DOPSWHS LP No.")
            {
                ApplicationArea = All;
                Editable = IsConsumption;
                ToolTip = 'Sarfiyat satırında kullanılan LP numarasını seçin. Kayıt sırasında bu LP miktarı da düşer.';
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        IsConsumption := Rec."Entry Type" = Rec."Entry Type"::Consumption;
    end;

    var
        IsConsumption: Boolean;
}
