pageextension 72313 "DOPSWHS Item Ledger Entries" extends "Item Ledger Entries"
{
    layout
    {
        addafter("Lot No.")
        {
            field("DOPSWHS LP No."; Rec."DOPSWHS LP No.")
            {
                ApplicationArea = All;
                Caption = 'LP No.';
                ToolTip = 'Bu madde defteri girişinin ilişkili olduğu taşıma kabı (LP) numarasını gösterir.';
                DrillDown = true;

                trigger OnDrillDown()
                var
                    LPHeader: Record "DOPSWHS LP Header";
                begin
                    if (Rec."DOPSWHS LP No." <> '') and LPHeader.Get(Rec."DOPSWHS LP No.") then
                        Page.Run(Page::"DOPSWHS LP Card", LPHeader);
                end;
            }
            field("DOPSWHS LP Nos."; Rec."DOPSWHS LP Nos.")
            {
                ApplicationArea = All;
                Caption = 'LP No.leri';
                ToolTip = 'Bu madde defteri girişi birden fazla taşıma kabından (LP) toplandıysa, tüketilen tüm kapları tüketim sırasıyla gösterir. Tek kaptan toplanan girişlerde boştur; o kap "LP No." alanındadır.';
                Editable = false;
            }
        }
    }

    actions
    {
        addlast(Processing)
        {
            action("DOPSWHS Refresh LP No.")
            {
                ApplicationArea = All;
                Caption = 'LP Bilgisini Yenile';
                ToolTip = 'Seçili madde defteri girişlerinin LP bilgisini deftere nakledilmiş ambar kayıtlarından veya sonradan oluşturulmuş tek ve kesin LP eşleşmesinden yeniden getirir.';
                Image = RefreshLines;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                var
                    SelectedItemLedgerEntry: Record "Item Ledger Entry";
                    LpPropagation: Codeunit "DOPSWHS LP Propagation";
                    UpdatedCount: Integer;
                    NotFoundCount: Integer;
                begin
                    CurrPage.SetSelectionFilter(SelectedItemLedgerEntry);
                    if SelectedItemLedgerEntry.FindSet(true) then
                        repeat
                            if LpPropagation.BackfillItemLedgerEntryLp(SelectedItemLedgerEntry) then
                                UpdatedCount += 1
                            else
                                NotFoundCount += 1;
                        until SelectedItemLedgerEntry.Next() = 0;

                    CurrPage.Update(false);
                    Message(
                        '%1 kayıt için LP bilgisi doğrulandı/güncellendi. %2 kayıt için ilişkili LP bulunamadı.',
                        UpdatedCount, NotFoundCount);
                end;
            }
        }
    }
}
