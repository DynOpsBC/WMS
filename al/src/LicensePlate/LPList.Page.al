page 72070 "DOPSWHS LP List"
{
    Caption = 'License Plates';
    AdditionalSearchTerms = 'LP Listesi, LP';
    PageType = List;
    SourceTable = "DOPSWHS LP Header";
    SourceTableView = sorting(Status, "Location Code");
    CardPageId = "DOPSWHS LP Card";
    ApplicationArea = All;
    UsageCategory = Lists;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; Editable = not HasContent; ToolTip = 'İçinde ürün olan LP''nin lokasyonu yalnız kayıtlı LP taşıma işlemiyle değişir.'; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; Editable = not HasContent; ToolTip = 'İçinde ürün olan LP''nin gözü yalnız kayıtlı LP taşıma işlemiyle (terminal ad-hoc taşıma) değişir; burada elle değiştirmek stoğu taşımaz.'; }
                field("Line Count"; Rec."Line Count") { ApplicationArea = All; }
                field("Total Quantity"; Rec."Total Quantity") { ApplicationArea = All; }
                field("Last Modified DateTime"; Rec."Last Modified DateTime")
                {
                    ApplicationArea = All;
                    Caption = 'Son LP İşlemi';
                    ToolTip = 'LP kaydındaki son güncelleme zamanıdır. Yakın zamanda taşınan LP''leri bulmak için sıralayın veya filtreleyin.';
                }
                field("LP Template Code"; Rec."LP Template Code") { ApplicationArea = All; }
                field("Parent LP No."; Rec."Parent LP No.") { ApplicationArea = All; }
                field(SSCC; Rec.SSCC) { ApplicationArea = All; }
                field("Assigned Document Type"; Rec."Assigned Document Type") { ApplicationArea = All; }
                field("Assigned Document No."; Rec."Assigned Document No.") { ApplicationArea = All; }
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(FindProductionPickRepairCandidates)
            {
                ApplicationArea = All;
                Caption = 'Üretim LP Onarım Adaylarını Bul';
                ToolTip = 'Location Code ve Bin Code filtrelerindeki kayıtlı üretim çekmelerini tarar. Filtre yoksa seçili LP satırının depo/gözünü kullanır. Tarama hiçbir kaydı değiştirmez.';
                Image = Search;
                trigger OnAction()
                var
                    SelectedLPs: Record "DOPSWHS LP Header";
                    Candidates: Page "DOPSWHS Prod Pick Candidates";
                begin
                    SelectedLPs.CopyFilters(Rec);
                    if SelectedLPs.GetFilter("Location Code") = '' then
                        SelectedLPs.SetRange("Location Code", Rec."Location Code");
                    if SelectedLPs.GetFilter("Bin Code") = '' then
                        SelectedLPs.SetRange("Bin Code", Rec."Bin Code");
                    Candidates.SetLpScope(SelectedLPs);
                    Candidates.RunModal();
                end;
            }
            action(LpStockReconciliation)
            {
                ApplicationArea = All;
                Caption = 'LP Stok Mutabakat Raporu';
                ToolTip = 'Seçili LP''lerdeki her madde ve lot için konumdaki tüm gözlerde LP miktarını, BC göz bakiyesini ve kayıtlı üretim tüketimini karşılaştıran CSV indirir. Hiçbir kaydı değiştirmez.';
                Image = Report;
                trigger OnAction()
                var
                    Selected: Record "DOPSWHS LP Header";
                    Reconcile: Codeunit "DOPSWHS LP Prod Consumption";
                    Blob: Codeunit "Temp Blob";
                    WriteStream: OutStream;
                    ReportStream: InStream;
                    FileName: Text;
                begin
                    CurrPage.SetSelectionFilter(Selected);
                    Blob.CreateOutStream(WriteStream, TextEncoding::UTF8);
                    WriteStream.WriteText(Reconcile.BuildReconciliationCsv(Selected));
                    Blob.CreateInStream(ReportStream, TextEncoding::UTF8);
                    FileName := 'LP-stok-mutabakati.csv';
                    DownloadFromStream(ReportStream, '', '', '', FileName);
                end;
            }
            action(DebitUntrackedProductionPicks)
            {
                ApplicationArea = All;
                Caption = 'Üretime LP''siz Çekileni LP''lerden Düş';
                ToolTip = 'LP düzeltme gözlerinde (WMS Kurulum, ör. A.URETIM) LP''lerin raftakinden fazla göründüğü madde/lotlarda farkı, yalnız BC''den LP seçilmeden kaydedilmiş üretim çekmeleri kadar LP''lerden düşer. Önce o üretim emrine atanmış LP, sonra atanmamış, sonra diğer LP''ler. BC''de stok kaydı oluşturmaz; yalnız LP miktarı ve LP hareket kaydı değişir. Sayım/düzeltmeyle stok eklenmiş maddeleri ayrıca belirtir. Önce ne yapılacağını gösterir.';
                Image = Reconcile;
                trigger OnAction()
                var
                    Repair: Codeunit "DOPSWHS LP Prod Consumption";
                    Summary: JsonObject;
                    Token: JsonToken;
                    RowToken: JsonToken;
                    Data: Text;
                    Detail: Text;
                    Blob: Codeunit "Temp Blob";
                    WriteStream: OutStream;
                    ReportStream: InStream;
                    FileName: Text;
                    Prompt: Text;
                    ReducedRows: Integer;
                    UnexplainedRows: Integer;
                    RowNo: Integer;
                begin
                    Data := Repair.DebitUntrackedProductionPicks(false);
                    Summary.ReadFrom(Data);
                    Summary.Get('reducedRows', Token); ReducedRows := Token.AsValue().AsInteger();
                    Summary.Get('unexplainedRows', Token); UnexplainedRows := Token.AsValue().AsInteger();
                    // One item per line: the lines are part of the dialog text
                    // itself, because a backslash inside a %1 value is not a
                    // line break.
                    Summary.Get('rows', Token);
                    foreach RowToken in Token.AsArray() do begin
                        RowNo += 1;
                        Detail += '\' + DebitRowText(RowToken, RowNo);
                    end;
                    if ReducedRows = 0 then begin
                        Message('Düşülecek LP miktarı yok. Hiçbir şey değişmedi.' + Detail);
                        exit;
                    end;
                    Prompt := Format(ReducedRows) + ' madde/lotta LP miktarı düşülecek (BC stoğu değişmez). ' +
                        'Açıklanamayan fark: ' + Format(UnexplainedRows) + ' satır (dokunulmaz).\' +
                        'Sıra: Madde · Lot · LP''de → Rafta · Düşülecek · Hangi LP''den\' + Detail + '\\Onaylıyor musunuz?';
                    if not Confirm(Prompt, false) then
                        exit;
                    Data := Repair.DebitUntrackedProductionPicks(true);
                    Blob.CreateOutStream(WriteStream, TextEncoding::UTF8);
                    WriteStream.WriteText(Data);
                    Blob.CreateInStream(ReportStream, TextEncoding::UTF8);
                    FileName := 'LP-uretim-dusum-sonucu.json';
                    DownloadFromStream(ReportStream, '', '', '', FileName);
                    CurrPage.Update(false);
                end;
            }
            action(RepairLegacyStockSources)
            {
                ApplicationArea = All;
                Caption = 'Eksik Kaynakları Toplu Bağla';
                ToolTip = 'Listedeki filtrelere uyan aktif LP satırlarını ürün, varyant, lot, seri, lokasyon ve varsa kaynak belge/SKT ile eşleştirir. Ayrılabilir miktarı yeterli tek bir giriş varsa bağlar; birden fazla adayı raporlar. Stok miktarı ve raf değişmez.';
                Image = Entries;
                trigger OnAction()
                var
                    Scope: Record "DOPSWHS LP Header";
                    Mgt: Codeunit "DOPSWHS LP Management";
                    Summary: JsonObject;
                    Token: JsonToken;
                    Data: Text;
                    ReportStream: InStream;
                    WriteStream: OutStream;
                    Blob: Codeunit "Temp Blob";
                    FileName: Text;
                    Eligible: Integer;
                    Skipped: Integer;
                begin
                    Scope.CopyFilters(Rec);
                    Data := Mgt.RepairMissingStockSources(Scope, false);
                    Summary.ReadFrom(Data);
                    Summary.Get('eligible', Token); Eligible := Token.AsValue().AsInteger();
                    Summary.Get('skipped', Token); Skipped := Token.AsValue().AsInteger();
                    if Eligible > 0 then
                        if Confirm('%1 satır tek bir kaynakla eşleşti. %2 satır otomatik bağlanmayacak. Listedeki filtrelere uyan bu kayıtlar topluca bağlansın mı?', false, Eligible, Skipped) then
                            Data := Mgt.RepairMissingStockSources(Scope, true);
                    Blob.CreateOutStream(WriteStream, TextEncoding::UTF8);
                    WriteStream.WriteText(Data);
                    Blob.CreateInStream(ReportStream, TextEncoding::UTF8);
                    FileName := 'LP-kaynak-baglanti-raporu.json';
                    DownloadFromStream(ReportStream, '', '', '', FileName);
                    CurrPage.Update(false);
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        LPLine.SetRange("LP No.", Rec."No.");
        HasContent := not LPLine.IsEmpty();
    end;

    local procedure DebitRowText(RowToken: JsonToken; RowNo: Integer): Text
    var
        Row: JsonObject;
        Value: JsonToken;
        Line: Text;
    begin
        Row := RowToken.AsObject();
        Line := Format(RowNo) + ') ';
        if Row.Get('itemNo', Value) then
            Line += Value.AsValue().AsText();
        if Row.Get('lotNo', Value) then
            if Value.AsValue().AsText() <> '' then
                Line += ' · Lot ' + Value.AsValue().AsText();
        if Row.Get('lpQuantity', Value) then
            Line += ' · LP''de ' + Format(Value.AsValue().AsDecimal());
        if Row.Get('binQuantity', Value) then
            Line += ' → rafta ' + Format(Value.AsValue().AsDecimal());
        if Row.Get('reduced', Value) then
            Line += ' · düşülecek ' + Format(Value.AsValue().AsDecimal());
        if Row.Get('allocation', Value) then
            if Value.AsValue().AsText() <> '' then
                Line += ' · ' + Value.AsValue().AsText();
        if Row.Get('note', Value) then
            if Value.AsValue().AsText() <> '' then
                Line += '\      ! ' + Value.AsValue().AsText();
        // The whole text is the dialog's format string: keep its placeholder
        // characters out of the data.
        exit(Line.Replace('%', ' ').Replace('#', ' '));
    end;

    local procedure PickRowText(RowToken: JsonToken): Text
    var
        Row: JsonObject;
        Value: JsonToken;
        Line: Text;
    begin
        Row := RowToken.AsObject();
        if Row.Get('document', Value) then
            Line := Value.AsValue().AsText();
        if Row.Get('lineNo', Value) then
            Line += ' satır ' + Value.AsValue().AsText();
        if Row.Get('itemNo', Value) then
            Line += ' ' + Value.AsValue().AsText();
        if Row.Get('quantityBase', Value) then
            Line += ' ' + Value.AsValue().AsText();
        if Row.Get('fromBin', Value) then
            Line += ' (' + Value.AsValue().AsText();
        if Row.Get('toBin', Value) then
            Line += ' -> ' + Value.AsValue().AsText();
        Line += ')';
        if Row.Get('result', Value) then
            Line += ': ' + Value.AsValue().AsText();
        exit(Line);
    end;

    local procedure RowText(RowToken: JsonToken): Text
    var
        Row: JsonObject;
        Value: JsonToken;
        Line: Text;
        FromBin: Text;
    begin
        Row := RowToken.AsObject();
        if Row.Get('lpNo', Value) then
            Line := Value.AsValue().AsText();
        if Row.Get('fromBin', Value) then
            if not Value.AsValue().IsNull() then
                FromBin := Value.AsValue().AsText();
        if (FromBin <> '') and Row.Get('toBin', Value) then
            Line += ' (' + FromBin + ' -> ' + Value.AsValue().AsText() + ')';
        if Row.Get('result', Value) then
            Line += ': ' + Value.AsValue().AsText();
        exit(Line);
    end;

    var
        HasContent: Boolean;
}
