/// <summary>
/// BADE (24 Eyl 2026): asks which bin the missing LP stock should be taken
/// from ("Seçili LP'lerin Eksik Stoğunu Seçilen Gözden Tamamla").
/// </summary>
page 72410 "DOPSWHS LP Source Bin Dialog"
{
    Caption = 'Kaynak Göz Seçin';
    PageType = StandardDialog;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                ShowCaption = false;
                field(Info; InfoTxt)
                {
                    ApplicationArea = All;
                    Caption = 'Açıklama';
                    Editable = false;
                    MultiLine = true;
                    ShowCaption = false;
                }
                field(LocationCode; LocationCode)
                {
                    ApplicationArea = All;
                    Caption = 'Lokasyon';
                    Editable = false;
                }
                field(SourceBin; SourceBin)
                {
                    ApplicationArea = All;
                    Caption = 'Kaynak göz';
                    ToolTip = 'Seçili LP''lerin eksik stoğunun alınacağı göz (örnek: A.TOPLAM). Yalnız bu gözdeki, başka LP''ye ait olmayan stok kullanılır.';

                    trigger OnLookup(var Text: Text): Boolean
                    var
                        Bin: Record Bin;
                    begin
                        Bin.SetRange("Location Code", LocationCode);
                        if Page.RunModal(0, Bin) = Action::LookupOK then begin
                            Text := Bin.Code;
                            exit(true);
                        end;
                    end;

                    trigger OnValidate()
                    var
                        Bin: Record Bin;
                    begin
                        if SourceBin <> '' then
                            if not Bin.Get(LocationCode, SourceBin) then
                                Error('%1 gözü %2 lokasyonunda yok.', SourceBin, LocationCode);
                    end;
                }
            }
        }
    }

    trigger OnOpenPage()
    begin
        InfoTxt := 'LP''lerin A.URETIM gibi bulunduğu gözde eksik kalan miktarı, burada seçeceğiniz gözden tamamlar. Bir sonraki ekranda ne taşınacağını görüp onaylarsınız.';
    end;

    procedure SetLocation(NewLocationCode: Code[10])
    begin
        LocationCode := NewLocationCode;
    end;

    procedure GetSourceBin(): Code[20]
    begin
        exit(SourceBin);
    end;

    var
        LocationCode: Code[10];
        SourceBin: Code[20];
        InfoTxt: Text;
}
