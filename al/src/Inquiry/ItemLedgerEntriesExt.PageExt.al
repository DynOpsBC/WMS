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
                ToolTip = 'Seçili girişlerin mevcut kaynak bağlantılarından LP bilgisini yeniler. Eksik kaynakları tahmin ederek bağlamaz; LP kartından Kaynak Girişi Bağla ile doğru giriş seçilmelidir.';
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
                        '%1 kayıt için LP bilgisi doğrulandı/güncellendi. %2 kayıt için kesin LP bağlantısı bulunamadı. Kaynağı eksik satırları LP kartından Kaynak Girişi Bağla ile kontrol edin.',
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
        // BADE (14 Eki 2026): 1.14.1.135 öncesi çok lotlu / çok dalgalı mal
        // kabulde kaynak giriş no lotlar arasında eziliyordu; başka lotun LP'si
        // gelmesin diye madde ve lot da eşleşmeli.
        SetEntryIdentityFilters(LPLine, ItemLedgerEntry);
        if LPLine.FindSet() then
            repeat
                AddLpNo(LPLine."LP No.", SeenLpNos);
            until LPLine.Next() = 0;

        // Legacy single/list stamps can point to a different product or lot.
        // A stamp is a candidate only; its current contents must match the entry.
        AddEntryLpNo(ItemLedgerEntry."DOPSWHS LP No.", ItemLedgerEntry, SeenLpNos);
        AddLpNosFromText(ItemLedgerEntry."DOPSWHS LP Nos.", ItemLedgerEntry, SeenLpNos);
    end;

    local procedure SetEntryIdentityFilters(var LPLine: Record "DOPSWHS LP Line"; ItemLedgerEntry: Record "Item Ledger Entry")
    begin
        LPLine.SetRange("Item No.", ItemLedgerEntry."Item No.");
        LPLine.SetRange("Variant Code", ItemLedgerEntry."Variant Code");
        LPLine.SetRange("Lot No.", ItemLedgerEntry."Lot No.");
        LPLine.SetRange("Serial No.", ItemLedgerEntry."Serial No.");
        LPLine.SetFilter(Quantity, '>0');
    end;

    local procedure AddEntryLpNo(LpNo: Code[20]; ItemLedgerEntry: Record "Item Ledger Entry"; var SeenLpNos: Dictionary of [Code[20], Boolean])
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if (LpNo = '') or SeenLpNos.ContainsKey(LpNo) then
            exit;
        LPLine.SetRange("LP No.", LpNo);
        SetEntryIdentityFilters(LPLine, ItemLedgerEntry);
        if not LPLine.IsEmpty() then
            AddLpNo(LpNo, SeenLpNos);
    end;

    local procedure AddLpNosFromText(LpNosText: Text; ItemLedgerEntry: Record "Item Ledger Entry"; var SeenLpNos: Dictionary of [Code[20], Boolean])
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
            AddEntryLpNo(CopyStr(LpNoText.Trim(), 1, 20), ItemLedgerEntry, SeenLpNos);
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
