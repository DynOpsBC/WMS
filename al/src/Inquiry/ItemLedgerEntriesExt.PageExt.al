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
            action("DOPSWHS Print All LP MTE")
            {
                ApplicationArea = All;
                Caption = 'Tüm LP MTE Etiketleri';
                ToolTip = 'Seçili madde defteri girişlerine bağlı tüm LP''ler için, her LP ayrı sayfa olacak şekilde Madde Tanımlama Etiketi açar.';
                Image = Print;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                var
                    SelectedItemLedgerEntry: Record "Item Ledger Entry";
                    LPHeader: Record "DOPSWHS LP Header";
                    SeenLpNos: Dictionary of [Code[20], Boolean];
                    LpFilter: Text;
                begin
                    CurrPage.SetSelectionFilter(SelectedItemLedgerEntry);
                    if SelectedItemLedgerEntry.FindSet() then
                        repeat
                            CollectItemLedgerEntryLpNos(SelectedItemLedgerEntry, SeenLpNos);
                        until SelectedItemLedgerEntry.Next() = 0;

                    LpFilter := BuildLpFilter(SeenLpNos);
                    if LpFilter = '' then
                        Error('Seçili madde defteri girişlerine bağlı, etiketlenebilir LP bulunamadı. Önce LP Bilgisini Yenile işlemini çalıştırın.');

                    LPHeader.SetFilter("No.", LpFilter);
                    Report.RunModal(Report::"DOPSWHS MTE LP Report", true, false, LPHeader);
                end;
            }
        }
    }

    local procedure CollectItemLedgerEntryLpNos(ItemLedgerEntry: Record "Item Ledger Entry"; var SeenLpNos: Dictionary of [Code[20], Boolean])
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("Source Item Ledger Entry No.", ItemLedgerEntry."Entry No.");
        LPLine.SetFilter(Quantity, '>0');
        if LPLine.FindSet() then
            repeat
                AddLpNo(LPLine."LP No.", SeenLpNos);
            until LPLine.Next() = 0;

        // Posted consumption entries can reference their LPs only through the
        // propagated single/list fields after the source LP lines were consumed.
        AddLpNo(ItemLedgerEntry."DOPSWHS LP No.", SeenLpNos);
        AddLpNosFromText(ItemLedgerEntry."DOPSWHS LP Nos.", SeenLpNos);
    end;

    local procedure AddLpNosFromText(LpNosText: Text; var SeenLpNos: Dictionary of [Code[20], Boolean])
    var
        SeparatorPosition: Integer;
        LpNoText: Text;
    begin
        while LpNosText <> '' do begin
            SeparatorPosition := StrPos(LpNosText, ',');
            if SeparatorPosition = 0 then begin
                LpNoText := LpNosText;
                Clear(LpNosText);
            end else begin
                LpNoText := CopyStr(LpNosText, 1, SeparatorPosition - 1);
                LpNosText := CopyStr(LpNosText, SeparatorPosition + 1);
            end;
            AddLpNo(CopyStr(LpNoText.Trim(), 1, 20), SeenLpNos);
        end;
    end;

    local procedure AddLpNo(LpNo: Code[20]; var SeenLpNos: Dictionary of [Code[20], Boolean])
    var
        LPHeader: Record "DOPSWHS LP Header";
    begin
        if (LpNo = '') or SeenLpNos.ContainsKey(LpNo) then
            exit;
        if not LPHeader.Get(LpNo) then
            exit;
        SeenLpNos.Add(LpNo, true);
    end;

    local procedure BuildLpFilter(SeenLpNos: Dictionary of [Code[20], Boolean]): Text
    var
        LpNo: Code[20];
        LpFilter: Text;
    begin
        foreach LpNo in SeenLpNos.Keys() do begin
            if LpFilter <> '' then
                LpFilter += '|';
            LpFilter += LpNo;
        end;
        exit(LpFilter);
    end;
}
