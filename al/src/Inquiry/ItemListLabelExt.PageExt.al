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
                ToolTip = 'Seçili maddelerin ZPL ürün etiketlerini seçeceğiniz etiket yazıcısına gönderir; terminaldeki Ürün Sorgu → Etiket Yazdır ile aynı çıktı. Birden fazla madde seçilebilir (tümünü seç ile bütün liste).';

                trigger OnAction()
                var
                    SelectedItem: Record Item;
                    LabelPrint: Codeunit "DOPSWHS BC Label Print";
                begin
                    // DKÇ (9 Eki 2026): tek madde yerine listede seçili bütün maddeler.
                    CurrPage.SetSelectionFilter(SelectedItem);
                    LabelPrint.PrintItemLabels(SelectedItem);
                end;
            }
        }
    }
}
