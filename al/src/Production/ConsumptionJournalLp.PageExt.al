pageextension 72318 "DOPSWHS Consumption Jnl LP" extends "Consumption Journal"
{
    layout
    {
        addafter("Bin Code")
        {
            field("DOPSWHS LP No."; Rec."DOPSWHS LP No.")
            {
                ApplicationArea = All;
                ToolTip = 'Üretim sarfiyatında kullanılan LP numarasını seçin. Kayıt sırasında bu LP miktarı da düşer.';
            }
        }
    }
}
