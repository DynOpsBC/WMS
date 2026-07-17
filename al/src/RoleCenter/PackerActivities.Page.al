page 72348 "DOPSWHS Packer Activities"
{
    // Packer ana ekranı: 3 worksheet kutusu — her kutu o moddaki AÇIK oturum
    // sayısını gösterir ve tıklanınca ilgili worksheet'i açar. El terminali
    // aynı Pack Session tablosuna yazdığı için terminalden başlatılan
    // oturumlar da bu sayaçlarda görünür.
    Caption = 'Packing Activities';
    PageType = CardPart;
    SourceTable = "DOPSWHS Warehouse Mgr Cue";
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            cuegroup(PackageWorksheets)
            {
                Caption = 'Package Worksheets';
                field("Open Bulk Pack Sessions"; Rec."Open Bulk Pack Sessions")
                {
                    Caption = 'Batch Package Worksheet';
                    ApplicationArea = All;
                    DrillDownPageId = "DOPSWHS Pack Station Bulk";
                }
                field("Open Batch Pack Sessions"; Rec."Open Batch Pack Sessions")
                {
                    Caption = 'Mono-SKU Package Worksheet';
                    ApplicationArea = All;
                    DrillDownPageId = "DOPSWHS Mono-SKU Pack Station";
                }
                field("Open Solo Pack Sessions"; Rec."Open Solo Pack Sessions")
                {
                    Caption = 'Solo Package Worksheet';
                    ApplicationArea = All;
                    DrillDownPageId = "DOPSWHS Pack Station Solo";
                }
            }
        }
    }

    trigger OnOpenPage()
    begin
        if not Rec.Get('') then begin
            Rec.Init();
            Rec.Insert(true);
        end;
    end;
}
