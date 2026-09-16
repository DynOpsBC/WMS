/// <summary>DKÇ (16 Eyl 2026): print the terminal's item label from the Item List.</summary>
pageextension 72324 "DOPSWHS Item List Label Ext" extends "Item List"
{
    actions
    {
        addlast(processing)
        {
            action(DOPSWHSPrintItemLabel)
            {
                Caption = 'Ürün Etiketi Yazdır';
                ApplicationArea = All;
                Image = Print;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Seçili maddenin ZPL ürün etiketini seçeceğiniz etiket yazıcısına gönderir; terminaldeki Ürün Sorgu → Etiket Yazdır ile aynı çıktı.';

                trigger OnAction()
                var
                    LabelPrint: Codeunit "DOPSWHS BC Label Print";
                begin
                    LabelPrint.PrintItemLabel(Rec);
                end;
            }
        }
    }
}
