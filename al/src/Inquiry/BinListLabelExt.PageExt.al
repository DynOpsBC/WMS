/// <summary>
/// DKÇ (16 Eyl 2026): print the terminal's bin label from Business Central
/// (same ZPL as Raf Sorgu → Etiket Yazdır) so a sample can be checked without
/// a hand terminal. The printer is chosen from the active ZPL printers.
/// </summary>
pageextension 72323 "DOPSWHS Bin List Label Ext" extends "Bin List"
{
    actions
    {
        addlast(processing)
        {
            action(DOPSWHSPrintBinLabel)
            {
                Caption = 'Raf Etiketi Yazdır';
                ApplicationArea = All;
                Image = Print;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Seçili rafın ZPL etiketini seçeceğiniz etiket yazıcısına gönderir; terminaldeki Raf Sorgu → Etiket Yazdır ile aynı çıktı.';

                trigger OnAction()
                var
                    LabelPrint: Codeunit "DOPSWHS BC Label Print";
                begin
                    LabelPrint.PrintBinLabel(Rec);
                end;
            }
        }
    }
}
