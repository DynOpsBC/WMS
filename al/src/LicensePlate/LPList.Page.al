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
                field(Status; Rec.Status) { ApplicationArea = All; Editable = false; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; Editable = false; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; Editable = false; ToolTip = 'LP rafı yalnız kayıtlı LP taşıma işlemiyle değiştirilir.'; }
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
}
